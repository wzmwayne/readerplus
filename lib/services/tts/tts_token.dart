// Sec-MS-GEC v2 令牌（移植自 edge-tts 参考实现的 drm.py）
//
// 微软把朗读令牌从 v1（单段 SHA-256）升级为 v2：
//   Sec-MS-GEC         = "<CS64 16 位>-<SHA256 64 位>"（大写十六进制）
//   Sec-MS-GEC-Version = "2-<chromium 版本>"
// 继续用 v1 时网关直接回 403 Forbidden（现象：朗读「合成失败」）。
// 这里的 SHA-256 是带盐变体（前 7 字节派生 IV），不能替换成标准实现。
//
// ignore_for_file: constant_identifier_names

const int _M = 0xFFFFFFFF;

const List<int> _ROUND = <int>[
  0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5,
  0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
  0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
  0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
  0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC,
  0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
  0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7,
  0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
  0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
  0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
  0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3,
  0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
  0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
  0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
  0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
  0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
];

const List<int> _SCHEDULE = <int>[
  0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA, 0xA622EE8C, 0xD1DD9491, 0xC0DD25A0,
  0xF9E70AB6, 0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33, 0xD258B060, 0x72766564,
];

const List<int> _STATE = <int>[
  0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A,
  0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2,
];

const List<int> _INITIAL = <int>[
  0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
  0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
];

/// CS64 的 14 组 (系数, 偏移)
const List<int> _CS64_COEF = <int>[3895366065, 3005677776, 1155409094, 2296378653, 1005282748, 693190712, 3365689651, 3005795295, 2367603217, 3557143765, 827258325, 652566332, 3911487921, 1618477510, 4037392853, 2192753147, 101076211, 4199654362, 3665427040, 545047652, 3201434976, 1010595059, 2314848760, 3536931681, 905590982, 3137643201, 3410617286, 3311559015];

const int _CS64_FACTOR = 0x82893933;
const int _CS64_ADJUSTMENT0 = 0xF2F90B1A;
const int _CS64_ADJUSTMENT1 = 0x0B1A0000;
const int _SHA256_ADJUSTMENT = 0xC9DC06A7;
const int _SIGMA0_ADJ = 0x059C0B80;
const int _SIGMA1_ADJ = 0x000B92C0;

/// 块常量：中段起算时把第 14 个常量换成 _SHA256_ADJUSTMENT
final List<int> _BLOCK = <int>[
  ..._ROUND.sublist(0, 14),
  _SHA256_ADJUSTMENT,
  ..._ROUND.sublist(15),
];

const String trustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
const String secMsGecVersion = '2-143.0.3650.75';

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & _M;

int _rol16(int v) {
  final m = v & _M;
  return ((m << 16) | (m >> 16)) & _M;
}

int _sigma0(int v) =>
    ((v >> 7) ^ (v << 25) ^ (v >> 18) ^ (v << 14) ^ (v >> 3)) & _M;

int _sigma1(int v) =>
    ((v >> 17) ^ (v << 15) ^ (v >> 19) ^ (v << 13) ^ (v >> 10)) & _M;

/// SHA-256 压缩；firstRound=14 时用块常量从中途起算。
List<int> _rounds(List<int> state, List<int> words, [int firstRound = 0]) {
  final k = firstRound == 14 ? _BLOCK : _ROUND;
  var a = state[0], b = state[1], c = state[2], dd = state[3];
  var e = state[4], f = state[5], g = state[6], h = state[7];
  for (var i = firstRound; i < 64; i++) {
    final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
    final ch = g ^ (e & (f ^ g));
    final t1 = (h + s1 + ch + k[i] + words[i]) & _M;
    final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
    final maj = (a & b) | (c & (a | b));
    final t2 = (s0 + maj) & _M;
    h = g;
    g = f;
    f = e;
    e = (dd + t1) & _M;
    dd = c;
    c = b;
    b = a;
    a = (t1 + t2) & _M;
  }
  return <int>[a, b, c, dd, e, f, g, h];
}

void _expand(List<int> words, [int firstWord = 16]) {
  for (var i = firstWord; i < 64; i++) {
    words.add((_sigma1(words[i - 2]) +
            words[i - 7] +
            _sigma0(words[i - 15]) +
            words[i - 16]) &
        _M);
  }
}

List<int> _init(List<int> data) {
  final words = <int>[
    ...List<int>.filled(14, 0),
    (data[0] << 16) | (data[1] << 8) | data[2],
  ];
  words.add((data[3] << 24) | (data[4] << 16) | (data[5] << 8) | data[6]);
  for (var index = 16; index < 30; index++) {
    var value = _SCHEDULE[index - 16];
    if (index - 2 >= 14) {
      final s = _sigma1(words[index - 2]);
      value += index == 16 ? (s ^ _SIGMA1_ADJ) : s;
    }
    if (index - 7 >= 14) value += words[index - 7];
    if (index - 15 >= 14) {
      final s = _sigma0(words[index - 15]);
      value += index == 29 ? (s ^ _SIGMA0_ADJ) : s;
    }
    words.add(value & _M);
  }
  words.add((_sigma1(words[28]) +
          words[23] +
          _sigma0(words[15]) +
          words[14] +
          _SHA256_ADJUSTMENT -
          _ROUND[14]) &
      _M);
  _expand(words, 31);
  final working = _rounds(_STATE, words, 14);
  return <int>[for (var i = 0; i < 8; i++) (_INITIAL[i] + working[i]) & _M];
}

/// 带盐 SHA-256（输入至少 7 字节）
List<int> _sha256(List<int> data) {
  final length = 57 + data.length;
  final padded = <int>[...data.sublist(7), 0x80];
  final zeros = (55 - length) % 64;
  padded.addAll(List<int>.filled(zeros, 0));
  final bitLen = length * 8;
  for (var i = 7; i >= 0; i--) {
    padded.add((bitLen >> (i * 8)) & 0xFF);
  }
  var state = _init(data.sublist(0, 7));
  for (var offset = 0; offset < padded.length; offset += 64) {
    final words = <int>[];
    for (var i = 0; i < 16; i++) {
      final b = offset + i * 4;
      words.add((padded[b] << 24) |
          (padded[b + 1] << 16) |
          (padded[b + 2] << 8) |
          padded[b + 3]);
    }
    _expand(words);
    final working = _rounds(state, words);
    state = <int>[for (var i = 0; i < 8; i++) (state[i] + working[i]) & _M];
  }
  final out = <int>[];
  for (final w in state) {
    out.addAll(<int>[(w >> 24) & 0xFF, (w >> 16) & 0xFF, (w >> 8) & 0xFF, w & 0xFF]);
  }
  return out;
}

List<int> _wordsLe4Even(List<int> data) {
  final padded = <int>[...data];
  while (padded.length % 4 != 0) {
    padded.add(0);
  }
  if (padded.isEmpty) return <int>[];
  final words = <int>[];
  for (var i = 0; i < padded.length; i += 4) {
    words.add(padded[i] |
        (padded[i + 1] << 8) |
        (padded[i + 2] << 16) |
        (padded[i + 3] << 24));
  }
  if (words.length.isOdd) words.add(0);
  return words;
}

List<int> _cs64(List<int> data, List<int> digest) {
  var keyA = (digest[0] | (digest[1] << 8) | (digest[2] << 16) | (digest[3] << 24)) & _M;
  var keyB = (digest[4] | (digest[5] << 8) | (digest[6] << 16) | (digest[7] << 24)) & _M;
  keyA |= 1;
  keyB |= 1;
  final factors = <int>[(keyA * _CS64_FACTOR) & _M, (keyB * _CS64_FACTOR) & _M];
  final terms = <int>[];
  final offsets = <int>[];
  for (var i = 0; i < _CS64_COEF.length ~/ 2; i++) {
    terms.add((_CS64_COEF[i * 2] * factors[i % 2]) & _M);
    offsets.add(_CS64_COEF[i * 2 + 1] & _M);
  }
  final words = _wordsLe4Even(<int>[0, ...data]);
  for (var index = 0; index < words.length; index++) {
    final word = words[index];
    var term = (word * (index.isEven ? keyA : keyB)) & _M;
    var offset = (_rol16(word) * (index.isEven ? 0xEF0569FB : 0xC31713DB)) & _M;
    if (index == 0) {
      term = (term + _CS64_ADJUSTMENT0 * factors[0]) & _M;
      offset = (offset + _CS64_ADJUSTMENT1) & _M;
    }
    terms.add(term);
    offsets.add(offset);
  }
  var swapAcc = 0, swapLast = 0, state = 0, acc = 0;
  for (var i = 0; i < terms.length; i += 2) {
    final x = terms[i], y = terms[i + 1];
    var t = _rol16((offsets[i] + x) & _M);
    var q = (t * 0x76F50F34) & _M;
    swapAcc = (swapAcc + ((_rol16(q) * 0xC3EFEA97 + q) & _M)) & _M;
    t = _rol16((offsets[i + 1] + y) & _M);
    q = (t * 0x1881CE3C) & _M;
    swapLast = (_rol16(q) * 0x35BD1EC9 + q) & _M;
    swapAcc = (swapAcc + swapLast) & _M;

    state = (state * keyA + x) & _M;
    state = (_rol16(state) * 0xCF98B111) & _M;
    state = (_rol16(state) * 0x87085B9F) & _M;
    state = (_rol16(state) * 0x12CEB96D) & _M;
    state = (_rol16(state) * 0x257E1D83) & _M;
    acc = (acc + state) & _M;
    t = (state * keyB + y) & _M;
    t = (_rol16(t) * 0xA27416F5) & _M;
    t = (_rol16(t) * 0xD38396FF) & _M;
    state = (_rol16((_rol16(t) * 0x7C932B89) & _M) * 0xBFA49F69) & _M;
    acc = (acc + state) & _M;
  }
  return <int>[swapLast ^ state, swapAcc ^ acc];
}

String _hexLE(int v) {
  final b = <int>[v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
  return b.map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
}

String _hex(List<int> bytes) =>
    bytes.map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase()).join();

String _tokenHash(List<int> data) {
  final digest = _sha256(data);
  final cs = _cs64(data, digest);
  return '${_hexLE(cs[0])}${_hexLE(cs[1])}-${_hex(digest)}';
}

/// 生成 Sec-MS-GEC v2 令牌；[unixTimestamp] 仅供测试。
String secMsGecV2([double? unixTimestamp]) {
  var ticks =
      unixTimestamp ?? DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0;
  ticks += 11644473600.0;
  ticks -= ticks % 300;
  ticks *= 10000000.0;
  return _tokenHash('${ticks.toStringAsFixed(0)}$trustedClientToken'.codeUnits);
}
