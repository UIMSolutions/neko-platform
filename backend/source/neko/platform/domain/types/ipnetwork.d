/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// IP addresses and networks (CIDR), IPv4 and IPv6. IPv4 is kept as an
/// IPv4-mapped IPv6 address, so one comparison covers both families.
module neko.platform.domain.types.ipnetwork;

import std.algorithm : canFind, count, startsWith;
import std.array : split;
import std.conv : to;
import std.format : format;
import std.string : indexOf, strip, toLower;
import neko.platform.domain.exceptions;

@safe:

struct IpAddress {
  ubyte[16] bytes;

  bool isV4() const pure nothrow {
    foreach (i; 0 .. 10)
      if (bytes[i] != 0)
        return false;
    return bytes[10] == 0xff && bytes[11] == 0xff;
  }

  bool isLoopback() const pure nothrow {
    if (isV4)
      return bytes[12] == 127;
    foreach (i; 0 .. 15)
      if (bytes[i] != 0)
        return false;
    return bytes[15] == 1;
  }

  /// "192.0.2.1", "2001:db8::1" (compressed, lower case).
  string toString() const pure {
    if (isV4)
      return format("%s.%s.%s.%s", bytes[12], bytes[13], bytes[14], bytes[15]);
    ushort[8] g;
    foreach (i; 0 .. 8)
      g[i] = cast(ushort)(bytes[2 * i] << 8 | bytes[2 * i + 1]);
    // longest run of zero groups (length >= 2) becomes "::"
    int bestStart = -1, bestLen = 0;
    for (int i = 0; i < 8;) {
      if (g[i] != 0) {
        i++;
        continue;
      }
      int j = i;
      while (j < 8 && g[j] == 0)
        j++;
      if (j - i > bestLen && j - i >= 2) {
        bestStart = i;
        bestLen = j - i;
      }
      i = j;
    }
    string s;
    for (int i = 0; i < 8; i++) {
      if (i == bestStart) {
        s ~= "::";
        i += bestLen - 1;
        continue;
      }
      if (s.length && s[$ - 1] != ':')
        s ~= ":";
      s ~= format("%x", g[i]);
    }
    return s;
  }
}

/// Parse an address; throws ValidationException. Accepts "[::1]" and IPv4-mapped forms.
IpAddress parseIpAddress(string text) pure {
  IpAddress a;
  if (!tryParseIpAddress(text, a))
    throw new ValidationException("'" ~ text.strip ~ "' is not an IP address");
  return a;
}

bool tryParseIpAddress(string text, out IpAddress result) pure nothrow {
  try {
    auto t = text.strip.toLower;
    if (t.length > 2 && t[0] == '[' && t[$ - 1] == ']')
      t = t[1 .. $ - 1];
    auto zone = t.indexOf('%'); // fe80::1%eth0
    if (zone > 0)
      t = t[0 .. zone];
    if (!t.canFind(':'))
      return parseV4(t, result.bytes[12 .. 16]) && setMapped(result);
    return parseV6(t, result.bytes);
  } catch (Exception)
    return false;
}

private bool setMapped(ref IpAddress a) pure nothrow {
  a.bytes[10] = 0xff;
  a.bytes[11] = 0xff;
  return true;
}

private bool parseV4(string t, ubyte[] target) pure {
  auto parts = t.split(".");
  if (parts.length != 4)
    return false;
  foreach (i, p; parts) {
    if (p.length == 0 || p.length > 3 || (p.length > 1 && p[0] == '0'))
      return false;
    foreach (c; p)
      if (c < '0' || c > '9')
        return false;
    auto v = p.to!int;
    if (v > 255)
      return false;
    target[i] = cast(ubyte) v;
  }
  return true;
}

private bool parseV6(string t, ref ubyte[16] target) pure {
  if (t.count("::") > 1)
    return false;
  // embedded IPv4 at the end ("::ffff:192.0.2.1") is handled below
  string[] head, tail;
  auto dbl = t.indexOf("::");
  string left = dbl >= 0 ? t[0 .. dbl] : t;
  string right = dbl >= 0 ? t[dbl + 2 .. $] : "";
  head = left.length ? left.split(":") : null;
  tail = right.length ? right.split(":") : null;
  ubyte[4] v4;
  bool hasV4;
  ref string[] last() return {
    return dbl >= 0 ? tail : head;
  }

  if (last.length && last[$ - 1].canFind('.')) {
    if (!parseV4(last[$ - 1], v4[]))
      return false;
    last = last[0 .. $ - 1];
    hasV4 = true;
  }
  auto groups = head.length + tail.length + (hasV4 ? 2 : 0);
  if (dbl < 0 && groups != 8)
    return false;
  if (dbl >= 0 && groups > 7)
    return false;
  ushort[] values;
  foreach (g; head ~ tail) {
    if (g.length == 0 || g.length > 4)
      return false;
    foreach (c; g)
      if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')))
        return false;
    values ~= g.to!ushort(16);
  }
  ubyte[16] b;
  size_t i;
  foreach (v; values[0 .. head.length]) {
    b[i++] = cast(ubyte)(v >> 8);
    b[i++] = cast(ubyte) v;
  }
  auto tailBytes = tail.length * 2 + (hasV4 ? 4 : 0);
  i = 16 - tailBytes;
  foreach (v; values[head.length .. $]) {
    b[i++] = cast(ubyte)(v >> 8);
    b[i++] = cast(ubyte) v;
  }
  if (hasV4)
    b[12 .. 16] = v4[];
  target = b;
  return true;
}

/// A network in CIDR notation ("10.0.0.0/8", "2001:db8::/32"); a bare
/// address is a network of one address.
struct IpNetwork {
  IpAddress base;
  /// Prefix length in the 128-bit space (IPv4 /24 → 120).
  int prefix = 128;

  this(string text) pure {
    auto t = text.strip;
    auto slash = t.indexOf('/');
    base = parseIpAddress(slash >= 0 ? t[0 .. slash] : t);
    auto max = base.isV4 ? 32 : 128;
    int bits = max;
    if (slash >= 0) {
      try
        bits = t[slash + 1 .. $].strip.to!int;
      catch (Exception)
        bits = -1;
      if (bits < 0 || bits > max)
        throw new ValidationException("'" ~ t ~ "': the prefix length must be 0 to " ~ max.to!string);
    }
    prefix = base.isV4 ? 96 + bits : bits;
    // normalize: clear host bits
    foreach (i; 0 .. 16) {
      auto keep = prefix - i * 8;
      if (keep <= 0)
        base.bytes[i] = 0;
      else if (keep < 8)
        base.bytes[i] &= cast(ubyte)(0xff << (8 - keep));
    }
    if (base.isV4 || prefix >= 96 && isMappedPrefix(base)) {
      base.bytes[10] = 0xff;
      base.bytes[11] = 0xff;
    }
  }

  bool contains(const IpAddress a) const pure nothrow {
    foreach (i; 0 .. 16) {
      auto keep = prefix - cast(int) i * 8;
      if (keep <= 0)
        return true;
      ubyte mask = keep >= 8 ? 0xff : cast(ubyte)(0xff << (8 - keep));
      if ((a.bytes[i] & mask) != (base.bytes[i] & mask))
        return false;
    }
    return true;
  }

  bool isV4() const pure nothrow {
    return prefix >= 96 && base.isV4;
  }

  /// "10.0.0.0/8", "192.0.2.7" (single addresses without prefix).
  string toString() const pure {
    auto bits = isV4 ? prefix - 96 : prefix;
    auto full = isV4 ? 32 : 128;
    return base.toString ~ (bits == full ? "" : "/" ~ bits.to!string);
  }
}

private bool isMappedPrefix(const IpAddress a) pure nothrow {
  foreach (i; 0 .. 10)
    if (a.bytes[i] != 0)
      return false;
  return a.bytes[10] == 0xff && a.bytes[11] == 0xff;
}

///
unittest {
  assert(parseIpAddress("192.0.2.1").toString == "192.0.2.1" && parseIpAddress("192.0.2.1").isV4);
  assert(parseIpAddress("[2001:DB8::1]").toString == "2001:db8::1");
  assert(parseIpAddress("::ffff:10.1.2.3").toString == "10.1.2.3"); // mapped = IPv4
  assert(parseIpAddress("::1").isLoopback && parseIpAddress("127.0.0.9").isLoopback);
  assert(parseIpAddress("fe80::1%eth0").toString == "fe80::1");
  assert(parseIpAddress("1:2:3:4:5:6:7:8").toString == "1:2:3:4:5:6:7:8");
  assert(parseIpAddress("2001:db8:0:0:1:0:0:1").toString == "2001:db8::1:0:0:1");
  foreach (bad; ["", "1.2.3", "256.1.1.1", "01.2.3.4", "1::2::3", "12345::", "g::1", "1:2:3:4:5:6:7:8:9", "example.org"]) {
    IpAddress a;
    assert(!tryParseIpAddress(bad, a), bad);
  }

  auto lan = IpNetwork("10.20.30.40/8");
  assert(lan.toString == "10.0.0.0/8" && lan.contains(parseIpAddress("10.255.0.1")));
  assert(!lan.contains(parseIpAddress("11.0.0.1")) && !lan.contains(parseIpAddress("::1")));
  assert(IpNetwork("192.0.2.7").toString == "192.0.2.7" && IpNetwork("192.0.2.7").contains(parseIpAddress("192.0.2.7")));
  auto v6 = IpNetwork("2001:db8::/32");
  assert(v6.contains(parseIpAddress("2001:db8:ffff::1")) && !v6.contains(parseIpAddress("2001:db9::1")));
  assert(IpNetwork("0.0.0.0/0").contains(parseIpAddress("8.8.8.8")) && !IpNetwork("0.0.0.0/0").contains(parseIpAddress("::2")));
  assert(IpNetwork("::/0").contains(parseIpAddress("1.2.3.4")));
  foreach (bad; ["10.0.0.0/33", "10.0.0.0/x", "::/129", "nonsense/8"]) {
    bool failed;
    try
      IpNetwork(bad);
    catch (ValidationException)
      failed = true;
    assert(failed, bad);
  }
}
