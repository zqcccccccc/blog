const test = require('node:test');
const assert = require('node:assert/strict');

process.env.TM_XMRIG_SCRIPT_PATH = require('node:path').join(
  __dirname,
  'fixtures',
  'log-stream-script.sh'
);

const { app } = require('../app');

function listen(serverApp) {
  return new Promise((resolve) => {
    const server = serverApp.listen(0, () => resolve(server));
  });
}

function close(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
}

test('GET / renders the home page with log stream bootstrap', async () => {
  const server = await listen(app);

  try {
    const port = server.address().port;
    const response = await fetch(`http://127.0.0.1:${port}/`);
    const body = await response.text();

    assert.equal(response.status, 200);
    assert.match(body, /\/logs\/stream/);
    assert.match(body, /Runtime Log/i);
  } finally {
    await close(server);
  }
});

test('GET /logs/stream streams shell output as SSE', async () => {
  const server = await listen(app);

  try {
    const port = server.address().port;
    const response = await fetch(`http://127.0.0.1:${port}/logs/stream`);
    const body = await response.text();

    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type') || '', /text\/event-stream/);
    assert.match(body, /data: \[INFO\] fixture stdout/);
    assert.match(body, /data: \[WARN\] fixture stderr/);
    assert.match(body, /event: done/);
  } finally {
    await close(server);
  }
});
