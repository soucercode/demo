const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PORT = Number(process.env.PORT || 8080);
const ADMIN_USERNAME = process.env.ADMIN_USERNAME;
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD;
const DB_FILE = process.env.DB_FILE || path.join(__dirname, 'license-db.json');

if (!ADMIN_USERNAME || !ADMIN_PASSWORD) {
  console.error('Set ADMIN_USERNAME and ADMIN_PASSWORD before starting the server.');
  process.exit(1);
}

function loadDB() {
  try { return JSON.parse(fs.readFileSync(DB_FILE, 'utf8')); }
  catch { return { keys: {}, sessions: {} }; }
}
function saveDB() { fs.writeFileSync(DB_FILE, JSON.stringify(db, null, 2)); }
const db = loadDB();

const durations = {
  '1hour': 60 * 60 * 1000,
  '2hour': 2 * 60 * 60 * 1000,
  '1day': 24 * 60 * 60 * 1000,
  '1week': 7 * 24 * 60 * 60 * 1000,
  '1month': 30 * 24 * 60 * 60 * 1000,
  '3month': 90 * 24 * 60 * 60 * 1000,
  'permanent': null
};

function json(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
  });
  res.end(data);
}
function body(req) {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', c => raw += c);
    req.on('end', () => { try { resolve(raw ? JSON.parse(raw) : {}); } catch (e) { reject(e); } });
    req.on('error', reject);
  });
}
function token() { return crypto.randomBytes(24).toString('hex'); }
function makeKey() {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let out = '';
  do {
    out = 'DHP-IPA-' + Array.from({ length: 6 }, () => alphabet[crypto.randomInt(alphabet.length)]).join('');
  } while (db.keys[out]);
  return out;
}
function auth(req) {
  const raw = req.headers.authorization || '';
  const t = raw.startsWith('Bearer ') ? raw.slice(7) : '';
  return !!t && !!db.sessions[t];
}
function expiryFor(duration) {
  const ms = durations[duration];
  return ms == null ? null : new Date(Date.now() + ms).toISOString();
}

const dashboard = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Proxy SHOP DHP — DASHBOARD ADMIN</title><style>body{font-family:system-ui;background:#090711;color:#eee;margin:0;padding:24px}main{max-width:1100px;margin:auto}.card{background:#141122;border:1px solid #392c5f;border-radius:18px;padding:18px;margin:14px 0}input,select,button{padding:11px;border-radius:10px;border:1px solid #55427f;background:#0d0a16;color:#fff}button{background:linear-gradient(90deg,#7c3aed,#06b6d4);cursor:pointer}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px}table{width:100%;border-collapse:collapse}td,th{padding:10px;border-bottom:1px solid #2b2440;text-align:left}.muted{color:#aaa}.hide{display:none}</style></head><body><main><h1>DASHBOARD ADMIN</h1><p class="muted">Proxy SHOP DHP · License Server</p><div id="login" class="card"><h2>Đăng nhập</h2><input id="u" placeholder="Tài khoản"><input id="p" type="password" placeholder="Mật khẩu"><button onclick="login()">Đăng nhập</button><p id="lm" class="muted"></p></div><div id="app" class="hide"><div class="card"><h2>Tạo Key Mới</h2><div class="grid"><select id="duration"><option value="1hour">1 Giờ</option><option value="2hour">2 Giờ</option><option value="1day">1 Ngày</option><option value="1day">1 Day</option><option value="1week">1 Tuần</option><option value="1month">1 Tháng</option><option value="3month">3 Tháng</option><option value="permanent">Vĩnh viễn</option></select><input id="qty" type="number" min="1" value="1" placeholder="Số lượng"><input id="maxDevices" type="number" min="1" value="1" placeholder="Số thiết bị/key"><button onclick="createKeys()">✨ Tạo Key</button></div><pre id="created"></pre></div><div class="card"><h2>Danh Sách Key</h2><button onclick="loadKeys()">Làm mới</button><table><thead><tr><th>KEY</th><th>THỜI HẠN</th><th>THIẾT BỊ</th><th>TRẠNG THÁI</th><th>HẾT HẠN</th></tr></thead><tbody id="rows"></tbody></table></div></div></main><script>let T='';async function api(path,opt={}){opt.headers={...(opt.headers||{}),Authorization:T?'Bearer '+T:'','Content-Type':'application/json'};let r=await fetch(path,opt);return r.json()}async function login(){let r=await api('/api/admin/login',{method:'POST',body:JSON.stringify({username:u.value,password:p.value})});if(r.token){T=r.token;loginDiv();loadKeys()}else lm.textContent=r.message||'Đăng nhập thất bại'}function loginDiv(){login.classList.add('hide');app.classList.remove('hide')}async function createKeys(){let r=await api('/api/admin/keys',{method:'POST',body:JSON.stringify({duration:duration.value,quantity:Number(qty.value),maxDevices:Number(maxDevices.value)})});created.textContent=(r.keys||[]).join('\n');loadKeys()}async function loadKeys(){let r=await api('/api/admin/keys');rows.innerHTML=(r.keys||[]).map(k=>'<tr><td>'+k.key+'</td><td>'+k.duration+'</td><td>'+k.devices.length+'/'+k.maxDevices+'</td><td>'+k.status+'</td><td>'+(k.expiresAt||'Vĩnh viễn')+'</td></tr>').join('')}</script></body></html>`;

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') return json(res, 204, {});
  if (req.method === 'GET' && req.url === '/') { res.writeHead(200, {'Content-Type':'text/html; charset=utf-8'}); return res.end(dashboard); }
  try {
    if (req.method === 'POST' && req.url === '/api/admin/login') {
      const b = await body(req);
      if (b.username === ADMIN_USERNAME && b.password === ADMIN_PASSWORD) {
        const t = token(); db.sessions[t] = { createdAt: Date.now() }; saveDB(); return json(res, 200, { token: t });
      }
      return json(res, 401, { message: 'Sai tài khoản hoặc mật khẩu' });
    }
    if (req.method === 'POST' && req.url === '/api/license/activate') {
      const b = await body(req); const key = String(b.key || '').toUpperCase(); const deviceId = String(b.deviceId || '');
      const record = db.keys[key];
      if (!record) return json(res, 404, { success:false, message:'Key không tồn tại', expiresAt:null });
      if (record.expiresAt && new Date(record.expiresAt) <= new Date()) return json(res, 403, { success:false, message:'Key đã hết hạn', expiresAt:record.expiresAt });
      if (!deviceId) return json(res, 400, { success:false, message:'Thiếu Device ID', expiresAt:record.expiresAt });
      if (!record.devices.includes(deviceId) && record.devices.length >= record.maxDevices) return json(res, 403, { success:false, message:'Key đã đủ số thiết bị', expiresAt:record.expiresAt });
      if (!record.devices.includes(deviceId)) record.devices.push(deviceId); saveDB();
      return json(res, 200, { success:true, message:'Kích hoạt thành công • Proxy SHOP DHP V1.0', expiresAt:record.expiresAt });
    }
    if (req.method === 'GET' && req.url === '/api/admin/keys') {
      if (!auth(req)) return json(res, 401, {message:'Unauthorized'});
      const keys = Object.values(db.keys).map(k => ({...k, status: k.expiresAt && new Date(k.expiresAt) <= new Date() ? 'Expired' : 'Active'}));
      return json(res, 200, {keys});
    }
    if (req.method === 'POST' && req.url === '/api/admin/keys') {
      if (!auth(req)) return json(res, 401, {message:'Unauthorized'});
      const b = await body(req); const duration = b.duration || '1day'; const quantity = Math.max(1, Math.min(100000, Number(b.quantity || 1))); const maxDevices = Math.max(1, Math.min(100000, Number(b.maxDevices || 1)));
      if (!(duration in durations)) return json(res, 400, {message:'Duration không hợp lệ'});
      const out=[]; for(let i=0;i<quantity;i++){const key=makeKey(); db.keys[key]={key,duration,maxDevices,devices:[],createdAt:new Date().toISOString(),expiresAt:expiryFor(duration)};out.push(key);} saveDB(); return json(res, 200, {keys:out});
    }
    return json(res, 404, {message:'Not found'});
  } catch (e) { console.error(e); return json(res, 500, {message:'Server error'}); }
});

server.listen(PORT, () => console.log(`License server listening on :${PORT}`));
