#!/usr/bin/env node
/**
 * Passo Client
 * Connects your local browser to the Passo relay server
 */

const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');

// Config
const CONFIG_PATH = path.join(process.env.HOME, '.passo/config.json');
const RELAY_URL = process.env.PASSO_RELAY || 'wss://api.getpasso.app';
const LOCAL_VNC_PORT = process.env.VNC_PORT || 6080;
const TOKEN = process.env.PASSO_TOKEN;
const QUIET = process.argv.includes('-q') || process.argv.includes('--quiet') || process.env.PASSO_QUIET === '1';

// Load config
let config = {};
try {
  config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
} catch (err) {
  // Config file optional if token provided via env
}

const token = TOKEN || config.token;
if (!token) {
  console.error('❌ No token. Set PASSO_TOKEN or run installer.');
  process.exit(1);
}

console.log('🔌 Passo Client');
console.log(`   Email: ${config.email || 'unknown'}`);
console.log(`   Slug: ${config.slug || 'unknown'}`);
console.log(`   Relay: ${RELAY_URL}`);
console.log(`   Local VNC: localhost:${LOCAL_VNC_PORT}`);
console.log('');

// Active viewer connections: viewerId -> { localWs, ready, buffer }
const viewers = new Map();

// Connect to relay
function connectToRelay() {
  console.log('🔄 Connecting to relay...');
  
  const ws = new WebSocket(`${RELAY_URL}/tunnel?token=${token}`);
  
  ws.on('open', () => {
    console.log('✅ Connected to relay');
    
    // Send ping every 30s to keep connection alive
    const pingInterval = setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.ping();
      }
    }, 30000);
    
    ws.on('close', () => clearInterval(pingInterval));
  });
  
  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data);
      
      switch (msg.type) {
        case 'connected':
          console.log(`🚇 Tunnel active: ${msg.slug}`);
          console.log(`🔗 Access: ${msg.browserUrl}`);
          break;
          
        case 'viewer_connect':
          handleViewerConnect(ws, msg.viewerId);
          break;
          
        case 'viewer_disconnect':
          handleViewerDisconnect(msg.viewerId);
          break;
          
        case 'data':
          handleViewerData(ws, msg.viewerId, msg.data);
          break;
          
        default:
          console.log('Unknown message:', msg.type);
      }
    } catch (err) {
      // Binary data or parse error, ignore
    }
  });
  
  ws.on('close', (code, reason) => {
    console.log(`❌ Disconnected (${code}): ${reason || 'unknown'}`);
    // Close all viewer connections
    viewers.forEach((viewer, viewerId) => {
      if (viewer.localWs) {
        try { viewer.localWs.close(); } catch (e) {}
      }
    });
    viewers.clear();
    console.log('🔄 Reconnecting in 5s...');
    setTimeout(connectToRelay, 5000);
  });
  
  ws.on('error', (err) => {
    console.error('WebSocket error:', err.message);
  });
  
  return ws;
}

// Handle new viewer
function handleViewerConnect(relayWs, viewerId) {
  if (!QUIET) console.log(`👁️  Viewer connected: ${viewerId}`);
  
  // Create viewer state with buffer for early messages
  const viewer = {
    localWs: null,
    ready: false,
    buffer: [],
  };
  viewers.set(viewerId, viewer);
  
  // Connect to local websockify
  const localWs = new WebSocket(`ws://localhost:${LOCAL_VNC_PORT}`, {
    // Handle binary properly
    perMessageDeflate: false,
  });
  
  localWs.binaryType = 'arraybuffer';
  
  localWs.on('open', () => {
    if (!QUIET) console.log(`   Local VNC connected for ${viewerId}`);
    viewer.localWs = localWs;
    viewer.ready = true;
    
    // Flush buffered messages
    if (viewer.buffer.length > 0) {
      if (!QUIET) console.log(`   Flushing ${viewer.buffer.length} buffered messages`);
      viewer.buffer.forEach((data) => {
        try {
          localWs.send(data);
        } catch (e) {}
      });
      viewer.buffer = [];
    }
  });
  
  localWs.on('message', (data) => {
    // Forward to relay
    if (relayWs.readyState === WebSocket.OPEN) {
      try {
        relayWs.send(JSON.stringify({
          viewerId,
          data: Buffer.from(data).toString('base64'),
        }));
      } catch (e) {
        console.error(`   Error sending to relay:`, e.message);
      }
    }
  });
  
  localWs.on('close', (code, reason) => {
    if (!QUIET) console.log(`   Local VNC closed for ${viewerId} (${code})`);
    viewers.delete(viewerId);
  });
  
  localWs.on('error', (err) => {
    console.error(`   Local VNC error for ${viewerId}:`, err.message);
    viewers.delete(viewerId);
  });
}

// Handle viewer disconnect
function handleViewerDisconnect(viewerId) {
  if (!QUIET) console.log(`👁️  Viewer disconnected: ${viewerId}`);
  const viewer = viewers.get(viewerId);
  if (viewer && viewer.localWs) {
    try {
      viewer.localWs.close(1000, 'Viewer disconnected');
    } catch (e) {}
  }
  viewers.delete(viewerId);
}

// Handle data from viewer
function handleViewerData(relayWs, viewerId, base64Data) {
  const viewer = viewers.get(viewerId);
  if (!viewer) return;
  
  const data = Buffer.from(base64Data, 'base64');
  
  if (viewer.ready && viewer.localWs && viewer.localWs.readyState === WebSocket.OPEN) {
    try {
      viewer.localWs.send(data);
    } catch (e) {
      console.error(`   Error sending to local VNC:`, e.message);
    }
  } else {
    // Buffer until ready
    viewer.buffer.push(data);
  }
}

// Start
connectToRelay();

// Keep alive
setInterval(() => {}, 1000);

// Handle exit
process.on('SIGINT', () => {
  console.log('\n🛑 Shutting down...');
  viewers.forEach((viewer) => {
    if (viewer.localWs) {
      try { viewer.localWs.close(); } catch (e) {}
    }
  });
  process.exit(0);
});
