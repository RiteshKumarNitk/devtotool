const https = require('https');

https.get('https://terabox.hnn.workers.dev/api/get-info?shorturl=1qW8xxxx', (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => console.log('Response 1:', data));
}).on('error', console.error);

https.get('https://terabox-dl.com/api/get-info?url=https://terabox.com/s/1qW8xxxx', (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => console.log('Response 2:', data));
}).on('error', console.error);
