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
const RELAY_URL = process.env.PASSO_RELAY || 'wss://passo-server-production.up.railway.app';
const LOCAL_VNC_PORT = process.env.VNC_PORT || 6080;
const TOKEN = process.env.PASSO_TOKEN;

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

// Active viewer connections
const viewers = new Map(); // viewerId -> local WebSocket

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
      console.error('Parse error:', err);
    }
  });
  
  ws.on('close', (code, reason) => {
    console.log(`❌ Disconnected (${code}): ${reason || 'unknown'}`);
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
  console.log(`👁️  Viewer connected: ${viewerId}`);
  
  // Connect to local websockify
  const localWs = new WebSocket(`ws://localhost:${LOCAL_VNC_PORT}`);
  
  localWs.on('open', () => {
    console.log(`   Local VNC connected for ${viewerId}`);
    viewers.set(viewerId, localWs);
  });
  
  localWs.on('message', (data) => {
    // Forward to relay
    if (relayWs.readyState === WebSocket.OPEN) {
      relayWs.send(JSON.stringify({
        viewerId,
        data: Buffer.from(data).toString('base64'),
      }));
    }
  });
  
  localWs.on('close', () => {
    console.log(`   Local VNC closed for ${viewerId}`);
    viewers.delete(viewerId);
  });
  
  localWs.on('error', (err) => {
    console.error(`   Local VNC error for ${viewerId}:`, err.message);
  });
}

// Handle viewer disconnect
function handleViewerDisconnect(viewerId) {
  console.log(`👁️  Viewer disconnected: ${viewerId}`);
  const localWs = viewers.get(viewerId);
  if (localWs) {
    localWs.close();
    viewers.delete(viewerId);
  }
}

// Handle data from viewer
function handleViewerData(relayWs, viewerId, base64Data) {
  const localWs = viewers.get(viewerId);
  if (localWs && localWs.readyState === WebSocket.OPEN) {
    localWs.send(Buffer.from(base64Data, 'base64'));
  }
}

// Start
connectToRelay();

// Keep alive
setInterval(() => {}, 1000);

// Handle exit
process.on('SIGINT', () => {
  console.log('\n🛑 Shutting down...');
  viewers.forEach((ws) => ws.close());
  process.exit(0);
});
