#!/usr/bin/env python3
# rocket-memory-mcp.py
# Rocket Routers — Claude Memory Node MCP Server
# Connects Claude to the memory API running on your Mycelium router
#
# Install: pip install mcp
# Config:  see claude_desktop_config.json instructions below
#
# Environment variables:
#   ROCKET_ROUTER_IP    — router LAN IP (default: 192.168.1.1)
#   ROCKET_MEMORY_PORT  — memory API port (default: 8765)
#   ROCKET_AUTH_TOKEN   — auth token from /etc/rocket/memory/auth.token

import asyncio
import json
import os
import urllib.request
import urllib.parse

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp import types

ROUTER_IP   = os.environ.get('ROCKET_ROUTER_IP',   '192.168.1.1')
ROUTER_PORT = os.environ.get('ROCKET_MEMORY_PORT', '8765')
AUTH_TOKEN  = os.environ.get('ROCKET_AUTH_TOKEN',  '')
BASE_URL    = f'http://{ROUTER_IP}:{ROUTER_PORT}/cgi-bin/rocket-memory'

def call_api(action, key=None, value=None):
    headers = {'Authorization': f'Bearer {AUTH_TOKEN}'}
    if action in ('read', 'list', 'stats'):
        params = {'action': action}
        if key:
            params['key'] = key
        url = BASE_URL + '?' + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers=headers)
    else:
        data = urllib.parse.urlencode({
            'action': action,
            'key':    key   or '',
            'value':  value or ''
        })
        req = urllib.request.Request(
            BASE_URL, data=data.encode(), headers=headers, method='POST'
        )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        return {'error': str(e)}

server = Server('rocket-memory')

@server.list_tools()
async def list_tools():
    return [
        types.Tool(
            name='read_memory',
            description='Read a memory from your Rocket Router Mycelium memory node.',
            inputSchema={
                'type': 'object',
                'properties': {
                    'key': {'type': 'string', 'description': 'The memory key to read'}
                },
                'required': ['key']
            }
        ),
        types.Tool(
            name='write_memory',
            description='Write a memory to your Rocket Router Mycelium memory node.',
            inputSchema={
                'type': 'object',
                'properties': {
                    'key':   {'type': 'string', 'description': 'Memory key'},
                    'value': {'type': 'string', 'description': 'Memory value to store'}
                },
                'required': ['key', 'value']
            }
        ),
        types.Tool(
            name='list_memories',
            description='List all memory keys stored on the Mycelium memory node.',
            inputSchema={'type': 'object', 'properties': {}}
        ),
        types.Tool(
            name='delete_memory',
            description='Delete a memory from the Mycelium memory node.',
            inputSchema={
                'type': 'object',
                'properties': {
                    'key': {'type': 'string', 'description': 'Memory key to delete'}
                },
                'required': ['key']
            }
        ),
        types.Tool(
            name='memory_stats',
            description='Get stats from the Mycelium memory node — quota, usage, Yggdrasil address.',
            inputSchema={'type': 'object', 'properties': {}}
        ),
    ]

@server.call_tool()
async def call_tool(name, arguments):
    if name == 'read_memory':
        result = call_api('read', key=arguments['key'])
    elif name == 'write_memory':
        result = call_api('write', key=arguments['key'], value=arguments['value'])
    elif name == 'list_memories':
        result = call_api('list')
    elif name == 'delete_memory':
        result = call_api('delete', key=arguments['key'])
    elif name == 'memory_stats':
        result = call_api('stats')
    else:
        result = {'error': f'Unknown tool: {name}'}

    return [types.TextContent(type='text', text=json.dumps(result, indent=2))]

async def main():
    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            server.create_initialization_options()
        )

if __name__ == '__main__':
    asyncio.run(main())
