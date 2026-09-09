const http = require('node:http');
const hiddenRoute = require('trace-route-package');

const port = Number(process.env.PORT || 8083);

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    return json(res, 200, {
      application: 'node-prepack-trace-lab',
      status: 'UP'
    });
  }

  if (req.url === hiddenRoute.path) {
    return json(res, 200, hiddenRoute.response);
  }

  res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
  res.end('Not found\n');
});

server.listen(port, '127.0.0.1', () => {
  console.log(`S05 listening on http://localhost:${port}/`);
  console.log(`Loaded route ${hiddenRoute.path} from trace-route-package`);
});

function json(res, status, value) {
  const body = JSON.stringify(value, null, 2) + '\n';
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
  res.end(body);
}
