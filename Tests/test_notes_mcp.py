#!/usr/bin/env python3
"""Black-box stdio MCP tests with isolated notes and no GUI activation."""
import concurrent.futures
import json
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXECUTABLE = ROOT / 'TD Capture.app/Contents/MacOS/TDCapture'


class Client:
    def __init__(self, directory):
        self.process = subprocess.Popen(
            [str(EXECUTABLE), '--mcp', '--notes-directory', str(directory), '--no-activate'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1,
        )
        self.counter = 0

    def send(self, message):
        self.process.stdin.write(json.dumps(message, ensure_ascii=False) + '\n')
        self.process.stdin.flush()

    def read(self):
        selector = selectors.DefaultSelector()
        selector.register(self.process.stdout, selectors.EVENT_READ)
        ready = selector.select(timeout=10)
        selector.close()
        if not ready:
            raise AssertionError('MCP response timed out')
        line = self.process.stdout.readline()
        if not line:
            raise AssertionError('MCP exited unexpectedly: ' + self.process.stderr.read())
        return json.loads(line)

    def request(self, method, params=None):
        self.counter += 1
        request = {'jsonrpc': '2.0', 'id': self.counter, 'method': method}
        if params is not None:
            request['params'] = params
        self.send(request)
        response = self.read()
        assert response['id'] == self.counter, response
        return response

    def initialize(self, version='2025-11-25'):
        response = self.request('initialize', {
            'protocolVersion': version, 'capabilities': {},
            'clientInfo': {'name': 'td-capture-tests', 'version': '1.0'},
        })
        self.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
        return response

    def call(self, name, **arguments):
        return self.request('tools/call', {'name': name, 'arguments': arguments})

    def create(self, content='A short script.', title='Test script'):
        return self.call('create_note', title=title, content=content)['result']['structuredContent']

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=10)
        stderr = self.process.stderr.read()
        self.process.stdout.close()
        self.process.stderr.close()
        if self.process.returncode != 0:
            raise AssertionError(stderr)


class NotesMCPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='td-capture-notes-test-')
        self.client = Client(self.temp.name)

    def tearDown(self):
        self.client.close()
        self.temp.cleanup()

    def test_lifecycle_and_discovery(self):
        self.assertEqual(self.client.request('tools/list')['error']['code'], -32002)
        initialized = self.client.initialize()
        self.assertEqual(initialized['result']['protocolVersion'], '2025-11-25')
        tools = self.client.request('tools/list')['result']['tools']
        self.assertEqual({tool['name'] for tool in tools}, {
            'create_note', 'list_notes', 'get_note', 'update_note', 'open_note', 'get_open_status',
        })
        self.assertNotIn('start_recording', {tool['name'] for tool in tools})
        self.assertEqual(self.client.request('ping')['result'], {})
        self.assertEqual(self.client.request('unknown')['error']['code'], -32601)
        self.assertEqual(self.client.call('unknown')['error']['code'], -32602)

    def test_round_trip_persistence_and_text(self):
        self.client.initialize()
        text = '# Demo\n\nKeep **Markdown**, emoji \U0001f3a5, and Unicode \u4f60\u597d literally.\n'
        note = self.client.create(content=text)
        self.assertEqual(note['revision'], 1)
        second = Client(self.temp.name)
        try:
            second.initialize('2025-06-18')
            loaded = second.call('get_note', id=note['id'])['result']['structuredContent']
            self.assertEqual(loaded['content'], text)
            notes = second.call('list_notes')['result']['structuredContent']['notes']
            self.assertEqual(notes[0]['id'], note['id'])
            self.assertNotIn('content', notes[0])
        finally:
            second.close()
        mode = (Path(self.temp.name) / (note['id'] + '.json')).stat().st_mode & 0o777
        self.assertEqual(mode, 0o600)

    def test_concurrent_revision_conflicts_do_not_overwrite(self):
        self.client.initialize()
        note = self.client.create()
        clients = [Client(self.temp.name), Client(self.temp.name)]
        try:
            for client in clients:
                client.initialize()
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(lambda pair: pair[1].call(
                    'update_note', id=note['id'], content='Writer ' + str(pair[0]), expected_revision=1,
                ), enumerate(clients)))
            self.assertEqual(sum(not result['result']['isError'] for result in results), 1)
            stored = self.client.call('get_note', id=note['id'])['result']['structuredContent']
            self.assertEqual(stored['revision'], 2)
            self.assertIn(stored['content'], ('Writer 0', 'Writer 1'))
            stale = self.client.call('update_note', id=note['id'], content='Stale overwrite', expected_revision=1)
            self.assertTrue(stale['result']['isError'])
            self.assertEqual(self.client.call('get_note', id=note['id'])['result']['structuredContent'], stored)
        finally:
            for client in clients:
                client.close()

    def test_open_request_stays_queued_without_gui(self):
        self.client.initialize()
        note = self.client.create()
        opened = self.client.call('open_note', id=note['id'])['result']['structuredContent']
        self.assertEqual(opened['status'], 'queued')
        self.assertFalse(opened['app_launch_requested'])
        status = self.client.call('get_open_status', request_id=opened['request_id'])['result']['structuredContent']
        self.assertEqual(status['status'], 'queued')
        self.assertEqual(status['noteId'], note['id'])

    def test_validation_and_protocol_errors(self):
        self.client.initialize()
        self.assertTrue(self.client.call('create_note', title=' ', content='test')['result']['isError'])
        self.assertTrue(self.client.call('create_note', title='Too big', content='a' * 1_048_577)['result']['isError'])
        self.assertTrue(self.client.call('get_note', id='../../outside')['result']['isError'])
        self.assertTrue(self.client.call('create_note', title='Unexpected', content='test', path='/tmp/invalid')['result']['isError'])
        note = self.client.create()
        self.assertTrue(self.client.call('update_note', id=note['id'], content='Bad revision', expected_revision=True)['result']['isError'])
        self.assertTrue(self.client.call('update_note', id=note['id'], content='Bad revision', expected_revision=1.5)['result']['isError'])
        self.client.process.stdin.write('{invalid json}\n')
        self.client.process.stdin.flush()
        self.assertEqual(self.client.read()['error']['code'], -32700)
        self.client.send({'jsonrpc': '2.0', 'id': True, 'method': 'ping'})
        self.assertEqual(self.client.read()['error']['code'], -32600)
        self.assertEqual(self.client.request('ping')['result'], {})


if __name__ == '__main__':
    unittest.main(verbosity=2)
