// Polyfill implementation for URL and URLSearchParams
(function(global) {
  if (typeof global.URL === 'function' && typeof global.URLSearchParams === 'function') {
    // Already exists in this test environment, but let's define PolyfillURL for testing
  }

  function URLSearchParamsPolyfill(init) {
    var pairs = [];
    var urlRef = null;

    function decode(str) {
      if (!str) return '';
      try {
        return decodeURIComponent(str.replace(/\+/g, ' '));
      } catch (e) {
        return str;
      }
    }

    function encode(str) {
      return encodeURIComponent(str)
        .replace(/%20/g, '+')
        .replace(/[!'()*]/g, function(c) {
          return '%' + c.charCodeAt(0).toString(16).toUpperCase();
        });
    }

    function syncToUrl() {
      if (urlRef) {
        var str = toString();
        urlRef._setSearchFromParams(str ? '?' + str : '');
      }
    }

    function parseString(str) {
      pairs = [];
      if (!str) return;
      if (str.charCodeAt(0) === 63 /* '?' */) {
        str = str.slice(1);
      }
      var parts = str.split('&');
      for (var i = 0; i < parts.length; i++) {
        var part = parts[i];
        if (!part) continue;
        var eq = part.indexOf('=');
        if (eq === -1) {
          pairs.push([decode(part), '']);
        } else {
          pairs.push([decode(part.slice(0, eq)), decode(part.slice(eq + 1))]);
        }
      }
    }

    if (typeof init === 'string') {
      parseString(init);
    } else if (init && typeof init === 'object') {
      if (Array.isArray(init)) {
        for (var i = 0; i < init.length; i++) {
          pairs.push([String(init[i][0]), String(init[i][1])]);
        }
      } else if (init instanceof URLSearchParamsPolyfill || (typeof URLSearchParams !== 'undefined' && init instanceof URLSearchParams)) {
        init.forEach(function(val, key) {
          pairs.push([key, val]);
        });
      } else {
        var keys = Object.keys(init);
        for (var k = 0; k < keys.length; k++) {
          var key = keys[k];
          pairs.push([String(key), String(init[key])]);
        }
      }
    }

    this.get = function(name) {
      var n = String(name);
      for (var i = 0; i < pairs.length; i++) {
        if (pairs[i][0] === n) return pairs[i][1];
      }
      return null;
    };

    this.getAll = function(name) {
      var n = String(name);
      var res = [];
      for (var i = 0; i < pairs.length; i++) {
        if (pairs[i][0] === n) res.push(pairs[i][1]);
      }
      return res;
    };

    this.has = function(name, value) {
      var n = String(name);
      var hasVal = arguments.length > 1;
      var v = hasVal ? String(value) : null;
      for (var i = 0; i < pairs.length; i++) {
        if (pairs[i][0] === n) {
          if (!hasVal || pairs[i][1] === v) return true;
        }
      }
      return false;
    };

    this.set = function(name, value) {
      var n = String(name);
      var v = String(value);
      var found = false;
      var newPairs = [];
      for (var i = 0; i < pairs.length; i++) {
        if (pairs[i][0] === n) {
          if (!found) {
            newPairs.push([n, v]);
            found = true;
          }
        } else {
          newPairs.push(pairs[i]);
        }
      }
      if (!found) newPairs.push([n, v]);
      pairs = newPairs;
      syncToUrl();
    };

    this.append = function(name, value) {
      pairs.push([String(name), String(value)]);
      syncToUrl();
    };

    this.delete = function(name, value) {
      var n = String(name);
      var hasVal = arguments.length > 1;
      var v = hasVal ? String(value) : null;
      pairs = pairs.filter(function(p) {
        if (p[0] !== n) return true;
        if (hasVal && p[1] !== v) return true;
        return false;
      });
      syncToUrl();
    };

    this.forEach = function(callback, thisArg) {
      for (var i = 0; i < pairs.length; i++) {
        callback.call(thisArg, pairs[i][1], pairs[i][0], this);
      }
    };

    this.keys = function() {
      return pairs.map(function(p) { return p[0]; })[Symbol.iterator]();
    };

    this.values = function() {
      return pairs.map(function(p) { return p[1]; })[Symbol.iterator]();
    };

    this.entries = function() {
      return pairs.slice()[Symbol.iterator]();
    };

    this[Symbol.iterator] = function() {
      return this.entries();
    };

    this.size = function() {
      return pairs.length;
    };

    var toString = function() {
      return pairs.map(function(p) {
        return encode(p[0]) + '=' + encode(p[1]);
      }).join('&');
    };

    this.toString = toString;

    this._setPairsFromRaw = function(rawSearch) {
      parseString(rawSearch);
    };

    this._bindToUrl = function(u) {
      urlRef = u;
    };
  }

  function resolvePath(relative, base) {
    if (!relative) return base || '/';
    if (relative.charCodeAt(0) === 47 /* '/' */) {
      var segs = relative.split('/');
      var out = [];
      for (var i = 0; i < segs.length; i++) {
        if (segs[i] === '..') {
          if (out.length > 1) out.pop();
        } else if (segs[i] !== '.') {
          out.push(segs[i]);
        }
      }
      return out.join('/') || '/';
    }

    var basePath = base || '/';
    var lastSlash = basePath.lastIndexOf('/');
    var dir = lastSlash !== -1 ? basePath.slice(0, lastSlash + 1) : '/';
    var combined = dir + relative;
    var parts = combined.split('/');
    var stack = [];
    for (var j = 0; j < parts.length; j++) {
      var p = parts[j];
      if (p === '..') {
        if (stack.length > 1) stack.pop();
      } else if (p !== '.') {
        stack.push(p);
      }
    }
    return stack.join('/') || '/';
  }

  function parseUrlParts(urlStr) {
    // Regex for URI: scheme:[//[user:pass@]host[:port]][path][?query][#hash]
    var regex = /^(?:([a-zA-Z][a-zA-Z0-9+.-]*):)?(?:\/\/([^\/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?$/;
    var match = urlStr.match(regex);
    if (!match) return null;

    var scheme = match[1] ? match[1].toLowerCase() : '';
    var authority = match[2];
    var path = match[3] || '';
    var query = match[4] !== undefined ? match[4] : '';
    var fragment = match[5] !== undefined ? match[5] : '';

    var username = '';
    var password = '';
    var host = '';
    var hostname = '';
    var port = '';

    if (authority !== undefined) {
      var userinfoEnd = authority.indexOf('@');
      var hostport = authority;
      if (userinfoEnd !== -1) {
        var userinfo = authority.slice(0, userinfoEnd);
        hostport = authority.slice(userinfoEnd + 1);
        var colon = userinfo.indexOf(':');
        if (colon !== -1) {
          username = userinfo.slice(0, colon);
          password = userinfo.slice(colon + 1);
        } else {
          username = userinfo;
        }
      }

      var portIdx = hostport.lastIndexOf(':');
      // If IPv6 [::1]:port
      var bracketIdx = hostport.indexOf(']');
      if (bracketIdx !== -1) {
        portIdx = hostport.indexOf(':', bracketIdx);
      }
      if (portIdx !== -1) {
        hostname = hostport.slice(0, portIdx).toLowerCase();
        port = hostport.slice(portIdx + 1);
      } else {
        hostname = hostport.toLowerCase();
        port = '';
      }
      host = port ? hostname + ':' + port : hostname;
    }

    return {
      scheme: scheme,
      username: username,
      password: password,
      host: host,
      hostname: hostname,
      port: port,
      path: path,
      query: query,
      hasQuery: match[4] !== undefined,
      fragment: fragment,
      hasFragment: match[5] !== undefined
    };
  }

  function URLPolyfill(input, base) {
    if (!input && input !== '') {
      throw new TypeError("Failed to construct 'URL': Invalid URL");
    }
    input = String(input).trim();

    var baseParsed = null;
    if (base !== undefined) {
      if (base instanceof URLPolyfill || (typeof URL !== 'undefined' && base instanceof URL)) {
        baseParsed = parseUrlParts(base.href);
      } else {
        baseParsed = parseUrlParts(String(base).trim());
      }
      if (!baseParsed || !baseParsed.scheme) {
        throw new TypeError("Failed to construct 'URL': Invalid base URL: " + base);
      }
    }

    var inputParsed = parseUrlParts(input);
    if (!inputParsed) {
      throw new TypeError("Failed to construct 'URL': Invalid URL: " + input);
    }

    var self = this;
    var _scheme = '';
    var _username = '';
    var _password = '';
    var _hostname = '';
    var _port = '';
    var _pathname = '/';
    var _search = '';
    var _hash = '';

    if (inputParsed.scheme) {
      // Input is absolute with scheme
      _scheme = inputParsed.scheme;
      _username = inputParsed.username;
      _password = inputParsed.password;
      _hostname = inputParsed.hostname;
      _port = inputParsed.port;
      _pathname = inputParsed.path || '/';
      if (_pathname.charCodeAt(0) !== 47 && (_scheme === 'http' || _scheme === 'https')) {
        _pathname = '/' + _pathname;
      }
      _pathname = resolvePath(_pathname, '/');
      _search = inputParsed.hasQuery ? '?' + inputParsed.query : '';
      _hash = inputParsed.hasFragment ? '#' + inputParsed.fragment : '';
    } else if (input.startsWith('//')) {
      // Protocol-relative URL
      if (!baseParsed) {
        throw new TypeError("Failed to construct 'URL': Invalid protocol-relative URL without base: " + input);
      }
      _scheme = baseParsed.scheme;
      _username = inputParsed.username;
      _password = inputParsed.password;
      _hostname = inputParsed.hostname;
      _port = inputParsed.port;
      _pathname = resolvePath(inputParsed.path || '/', '/');
      _search = inputParsed.hasQuery ? '?' + inputParsed.query : '';
      _hash = inputParsed.hasFragment ? '#' + inputParsed.fragment : '';
    } else if (baseParsed) {
      // Relative URL with base
      _scheme = baseParsed.scheme;
      _username = baseParsed.username;
      _password = baseParsed.password;
      _hostname = baseParsed.hostname;
      _port = baseParsed.port;

      if (input.charCodeAt(0) === 63 /* '?' */) {
        _pathname = baseParsed.path || '/';
        _search = '?' + inputParsed.query;
        _hash = inputParsed.hasFragment ? '#' + inputParsed.fragment : '';
      } else if (input.charCodeAt(0) === 35 /* '#' */) {
        _pathname = baseParsed.path || '/';
        _search = baseParsed.hasQuery ? '?' + baseParsed.query : '';
        _hash = '#' + inputParsed.fragment;
      } else if (input === '') {
        _pathname = baseParsed.path || '/';
        _search = baseParsed.hasQuery ? '?' + baseParsed.query : '';
        _hash = baseParsed.hasFragment ? '#' + baseParsed.fragment : '';
      } else {
        _pathname = resolvePath(inputParsed.path, baseParsed.path || '/');
        _search = inputParsed.hasQuery ? '?' + inputParsed.query : '';
        _hash = inputParsed.hasFragment ? '#' + inputParsed.fragment : '';
      }
    } else {
      throw new TypeError("Failed to construct 'URL': Invalid URL: " + input);
    }

    var searchParamsInstance = new URLSearchParamsPolyfill(_search);
    searchParamsInstance._bindToUrl(self);

    this._setSearchFromParams = function(newSearch) {
      _search = newSearch;
    };

    Object.defineProperty(this, 'protocol', {
      get: function() { return _scheme ? _scheme + ':' : ''; },
      set: function(val) {
        var s = String(val).replace(/:$/, '').toLowerCase();
        if (s) _scheme = s;
      }
    });

    Object.defineProperty(this, 'hostname', {
      get: function() { return _hostname; },
      set: function(val) { _hostname = String(val).toLowerCase(); }
    });

    Object.defineProperty(this, 'port', {
      get: function() { return _port; },
      set: function(val) {
        var p = String(val);
        _port = p === '80' && _scheme === 'http' ? '' : (p === '443' && _scheme === 'https' ? '' : p);
      }
    });

    Object.defineProperty(this, 'host', {
      get: function() { return _port ? _hostname + ':' + _port : _hostname; },
      set: function(val) {
        var str = String(val);
        var idx = str.lastIndexOf(':');
        if (idx !== -1) {
          _hostname = str.slice(0, idx).toLowerCase();
          _port = str.slice(idx + 1);
        } else {
          _hostname = str.toLowerCase();
          _port = '';
        }
      }
    });

    Object.defineProperty(this, 'pathname', {
      get: function() { return _pathname; },
      set: function(val) {
        var p = String(val);
        _pathname = p.charCodeAt(0) === 47 ? p : '/' + p;
      }
    });

    Object.defineProperty(this, 'search', {
      get: function() { return _search; },
      set: function(val) {
        var s = String(val);
        if (s && s.charCodeAt(0) !== 63) s = '?' + s;
        _search = s === '?' ? '' : s;
        searchParamsInstance._setPairsFromRaw(_search);
      }
    });

    Object.defineProperty(this, 'searchParams', {
      get: function() { return searchParamsInstance; }
    });

    Object.defineProperty(this, 'hash', {
      get: function() { return _hash; },
      set: function(val) {
        var h = String(val);
        if (h && h.charCodeAt(0) !== 35) h = '#' + h;
        _hash = h === '#' ? '' : h;
      }
    });

    Object.defineProperty(this, 'username', {
      get: function() { return _username; },
      set: function(val) { _username = String(val); }
    });

    Object.defineProperty(this, 'password', {
      get: function() { return _password; },
      set: function(val) { _password = String(val); }
    });

    Object.defineProperty(this, 'origin', {
      get: function() {
        if (!_scheme || !_hostname) return '';
        var h = _port ? _hostname + ':' + _port : _hostname;
        return _scheme + '://' + h;
      }
    });

    Object.defineProperty(this, 'href', {
      get: function() {
        var auth = _username ? _username + (_password ? ':' + _password : '') + '@' : '';
        var hostPart = _hostname ? '//' + auth + self.host : '';
        return self.protocol + hostPart + _pathname + _search + _hash;
      },
      set: function(val) {
        var parsed = new URLPolyfill(val);
        _scheme = parsed.protocol.replace(/:$/, '');
        _hostname = parsed.hostname;
        _port = parsed.port;
        _pathname = parsed.pathname;
        _search = parsed.search;
        _hash = parsed.hash;
        _username = parsed.username;
        _password = parsed.password;
        searchParamsInstance._setPairsFromRaw(_search);
      }
    });

    this.toString = function() {
      return this.href;
    };

    this.toJSON = function() {
      return this.href;
    };
  }

  URLPolyfill.canParse = function(url, base) {
    try {
      new URLPolyfill(url, base);
      return true;
    } catch (e) {
      return false;
    }
  };

  if (typeof global.URL === "undefined") global.URL = URLPolyfill;
  global.URLPolyfill = URLPolyfill;
  if (typeof global.URLSearchParams === "undefined") global.URLSearchParams = URLSearchParamsPolyfill;
  global.URLSearchParamsPolyfill = URLSearchParamsPolyfill;
})(typeof globalThis !== 'undefined' ? globalThis : this);

// Base64 atob & btoa polyfill
(function(global) {
  if (typeof global.btoa === 'undefined') {
    global.btoa = function(str) {
      var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
      var output = '';
      for (var block = 0, charCode, i = 0, map = chars;
           str.charAt(i | 0) || (map = '=', i % 1);
           output += map.charAt(63 & block >> 8 - i % 1 * 8)) {
        charCode = str.charCodeAt(i += 3/4);
        if (charCode > 0xFF) throw new Error("'btoa' failed: The string to be encoded contains characters outside of the Latin1 range.");
        block = block << 8 | charCode;
      }
      return output;
    };
  }
  if (typeof global.atob === 'undefined') {
    global.atob = function(input) {
      var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
      var str = String(input).replace(/=+$/, '');
      if (str.length % 4 === 1) throw new Error("'atob' failed: The string to be decoded is not correctly encoded.");
      var output = '';
      for (var bc = 0, bs = 0, buffer, i = 0;
           buffer = str.charAt(i++);
           ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer,
             bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
        buffer = chars.indexOf(buffer);
      }
      return output;
    };
  }
})(typeof globalThis !== 'undefined' ? globalThis : this);
