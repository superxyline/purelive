const fs = require('fs');
const src = fs.readFileSync('E:/codex/pure_live/lib/core/danmaku/proto/douyin.pb.dart', 'utf8');
const want = ['Response', 'Message', 'ChatMessage', 'RoomUserSeqMessage', 'GiftMessage', 'GiftStruct', 'Common', 'User', 'Image', 'PushFrame'];
for (const cls of want) {
  const re = new RegExp('class ' + cls + ' extends \\$pb\\.GeneratedMessage \\{([\\s\\S]*?)\\n\\}');
  const m = src.match(re);
  if (!m) { console.log('MISSING', cls); continue; }
  const lines = m[1].split('\n');
  const seen = new Set(); const out = [];
  for (const line of lines) {
    const im = line.match(/\.\.(\w+)(?:<[^>]*>)?\((\d+),/);
    if (!im) continue;
    const method = im[1], num = im[2];
    if (seen.has(num)) continue; seen.add(num);
    // name: last quoted non-empty string before fieldType/protoName end, prefer protoName
    let name = '';
    const pm = line.match(/protoName:\s*'(\w+)'/);
    if (pm && pm[1]) name = pm[1];
    if (!name) {
      const qs = line.match(/'(\w+)'/g);
      if (qs) { for (let i = qs.length - 1; i >= 0; i--) { if (qs[i].length > 3) { name = qs[i].slice(1, -1); break; } } }
    }
    out.push('  ' + name + ' = field ' + num + ' (' + method + ')');
  }
  console.log('== ' + cls + ' ==');
  console.log(out.join('\n'));
}
