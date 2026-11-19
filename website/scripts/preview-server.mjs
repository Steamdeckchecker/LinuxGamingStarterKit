// Preview of the built Worker; production uses the same fetch handler.
import http from 'node:http';
import worker from '../worker/index.js';
const index = process.argv.indexOf('--port');
const port = Number(process.env.PORT || (index >= 0 && process.argv[index + 1]) || 5173);
http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, `http://${request.headers.host}`);
    const result = await worker.fetch(new Request(url, {method: request.method}));
    response.writeHead(result.status, Object.fromEntries(result.headers));
    response.end(Buffer.from(await result.arrayBuffer()));
  } catch (error) {
    console.error(error.message);
    response.writeHead(500);
    response.end('Preview request failed');
  }
}).listen(port, '0.0.0.0', () => console.log(`Site preview listening on ${port}`));
