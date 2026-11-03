/**
 * a minimal HTTP/2 test server for the tests of the attribute httpVersion (LDEV-6470), it needs no library, only
 * what the JDK has, so the tests do not depend on a public server.
 *
 * modes (the argument mode of init):
 * - "tls-h2": TLS with ALPN, the server offers "h2" and "http/1.1", a client that offers h2 gets HTTP/2, any other
 *   client gets HTTP/1.1 on the same port
 * - "tls-h1": TLS with ALPN, the server offers only "http/1.1" (a server that can not speak HTTP/2)
 * - "h2c": plain text HTTP/2 with prior knowledge (a client that starts with the HTTP/2 preface), any other
 *   client gets HTTP/1.1
 *
 * - "h1": plain text, only HTTP/1.1 (a server that can not speak HTTP/2, a request with the HTTP/2 preface gets no
 *   HTTP/2 answer)
 *
 * the TLS modes use the keystore _h2/h2-test.p12 (self signed, localhost and 127.0.0.1), a test passes
 * getTrustStore() as trustStore to cfhttp.
 *
 * paths:
 * - /echo: 200, a text body with the protocol, method, path, authority, scheme, headers and body of the request
 * - /status/<n>: answers with the status n
 * - /redirect: 302 to /echo
 * - /slow: waits 3 seconds before it answers
 * - everything else: 200 with the body "ok"
 * every answer has the header x-test-server.
 *
 * the server handles every connection in its own thread, and every HTTP/2 connection can carry many streams, but
 * a stream is answered when the request is complete (no streaming).
 */
component {

	variables.CRLF = chr( 13 ) & chr( 10 );
	variables.PREFACE = "PRI * HTTP/2.0" & variables.CRLF & variables.CRLF & "SM" & variables.CRLF & variables.CRLF;
	variables.HUFFMAN_SPEC = "1ff8:13,7fffd8:23,fffffe2:28,fffffe3:28,fffffe4:28,fffffe5:28,fffffe6:28,fffffe7:28,fffffe8:28,ffffea:24,3ffffffc:30,fffffe9:28,fffffea:28,3ffffffd:30,fffffeb:28,fffffec:28,fffffed:28,fffffee:28,fffffef:28,ffffff0:28,ffffff1:28,ffffff2:28,3ffffffe:30,ffffff3:28,ffffff4:28,ffffff5:28,ffffff6:28,ffffff7:28,ffffff8:28,ffffff9:28,ffffffa:28,ffffffb:28,14:6,3f8:10,3f9:10,ffa:12,1ff9:13,15:6,f8:8,7fa:11,3fa:10,3fb:10,f9:8,7fb:11,fa:8,16:6,17:6,18:6,0:5,1:5,2:5,19:6,1a:6,1b:6,1c:6,1d:6,1e:6,1f:6,5c:7,fb:8,7ffc:15,20:6,ffb:12,3fc:10,1ffa:13,21:6,5d:7,5e:7,5f:7,60:7,61:7,62:7,63:7,64:7,65:7,66:7,67:7,68:7,69:7,6a:7,6b:7,6c:7,6d:7,6e:7,6f:7,70:7,71:7,72:7,fc:8,73:7,fd:8,1ffb:13,7fff0:19,1ffc:13,3ffc:14,22:6,7ffd:15,3:5,23:6,4:5,24:6,5:5,25:6,26:6,27:6,6:5,74:7,75:7,28:6,29:6,2a:6,7:5,2b:6,76:7,2c:6,8:5,9:5,2d:6,77:7,78:7,79:7,7a:7,7b:7,7ffe:15,7fc:11,3ffd:14,1ffd:13,ffffffc:28,fffe6:20,3fffd2:22,fffe7:20,fffe8:20,3fffd3:22,3fffd4:22,3fffd5:22,7fffd9:23,3fffd6:22,7fffda:23,7fffdb:23,7fffdc:23,7fffdd:23,7fffde:23,ffffeb:24,7fffdf:23,ffffec:24,ffffed:24,3fffd7:22,7fffe0:23,ffffee:24,7fffe1:23,7fffe2:23,7fffe3:23,7fffe4:23,1fffdc:21,3fffd8:22,7fffe5:23,3fffd9:22,7fffe6:23,7fffe7:23,ffffef:24,3fffda:22,1fffdd:21,fffe9:20,3fffdb:22,3fffdc:22,7fffe8:23,7fffe9:23,1fffde:21,7fffea:23,3fffdd:22,3fffde:22,fffff0:24,1fffdf:21,3fffdf:22,7fffeb:23,7fffec:23,1fffe0:21,1fffe1:21,3fffe0:22,1fffe2:21,7fffed:23,3fffe1:22,7fffee:23,7fffef:23,fffea:20,3fffe2:22,3fffe3:22,3fffe4:22,7ffff0:23,3fffe5:22,3fffe6:22,7ffff1:23,3ffffe0:26,3ffffe1:26,fffeb:20,7fff1:19,3fffe7:22,7ffff2:23,3fffe8:22,1ffffec:25,3ffffe2:26,3ffffe3:26,3ffffe4:26,7ffffde:27,7ffffdf:27,3ffffe5:26,fffff1:24,1ffffed:25,7fff2:19,1fffe3:21,3ffffe6:26,7ffffe0:27,7ffffe1:27,3ffffe7:26,7ffffe2:27,fffff2:24,1fffe4:21,1fffe5:21,3ffffe8:26,3ffffe9:26,ffffffd:28,7ffffe3:27,7ffffe4:27,7ffffe5:27,fffec:20,fffff3:24,fffed:20,1fffe6:21,3fffe9:22,1fffe7:21,1fffe8:21,7ffff3:23,3fffea:22,3fffeb:22,1ffffee:25,1ffffef:25,fffff4:24,fffff5:24,3ffffea:26,7ffff4:23,3ffffeb:26,7ffffe6:27,3ffffec:26,3ffffed:26,7ffffe7:27,7ffffe8:27,7ffffe9:27,7ffffea:27,7ffffeb:27,ffffffe:28,7ffffec:27,7ffffed:27,7ffffee:27,7ffffef:27,7fffff0:27,3ffffee:26,3fffffff:30";
	variables.STATIC_SPEC = ":authority=|:method=GET|:method=POST|:path=/|:path=/index.html|:scheme=http|:scheme=https|:status=200|:status=204|:status=206|:status=304|:status=400|:status=404|:status=500|accept-charset=|accept-encoding=gzip, deflate|accept-language=|accept-ranges=|accept=|access-control-allow-origin=|age=|allow=|authorization=|cache-control=|content-disposition=|content-encoding=|content-language=|content-length=|content-location=|content-range=|content-type=|cookie=|date=|etag=|expect=|expires=|from=|host=|if-match=|if-modified-since=|if-none-match=|if-range=|if-unmodified-since=|last-modified=|link=|location=|max-forwards=|proxy-authenticate=|proxy-authorization=|range=|referer=|refresh=|retry-after=|server=|set-cookie=|strict-transport-security=|transfer-encoding=|user-agent=|vary=|via=|www-authenticate=";

	public function init( string mode="tls-h2" ) {
		variables.mode = arguments.mode;
		// the modes without TLS
		variables.plain = listFindNoCase( "h2c,h1", arguments.mode ) > 0;
		if ( !listFindNoCase( "tls-h2,tls-h1,h2c,h1", variables.mode ) ) throw( message="unknown mode [#variables.mode#]" );
		variables.requests = [];
		variables.connections = 0;
		variables.stopped = false;
		variables.failure = "";
		variables.sockets = [];
		variables.threads = [];
		variables.trustStore = getDirectoryFromPath( getCurrentTemplatePath() ) & "_h2/h2-test.p12";

		// the huffman table of RFC 7541 (code:length of the symbols 0 to 256) and the static table
		variables.huffman = {};
		var i = 0;
		for ( var spec in listToArray( variables.HUFFMAN_SPEC ) ) {
			variables.huffman[ listLast( spec, ":" ) & ":" & inputBaseN( listFirst( spec, ":" ), 16 ) ] = i++;
		}
		variables.staticTable = [];
		for ( var spec in listToArray( variables.STATIC_SPEC, "|" ) ) {
			arrayAppend( variables.staticTable, { "name": listFirst( spec, "=" ), "value": find( "=", spec ) < len( spec ) ? mid( spec, find( "=", spec ) + 1, len( spec ) ) : "" } );
		}

		var inet = createObject( "java", "java.net.InetAddress" ).getByName( "127.0.0.1" );
		if ( variables.plain ) {
			variables.server = createObject( "java", "java.net.ServerSocket" ).init( javacast( "int", 0 ), javacast( "int", 50 ), inet );
		}
		else {
			var password = createObject( "java", "java.lang.String" ).init( "changeit" ).toCharArray();
			var ks = createObject( "java", "java.security.KeyStore" ).getInstance( "PKCS12" );
			var fis = createObject( "java", "java.io.FileInputStream" ).init( variables.trustStore );
			try {
				ks.load( fis, password );
			}
			finally {
				fis.close();
			}
			var kmf = createObject( "java", "javax.net.ssl.KeyManagerFactory" ).getInstance( "SunX509" );
			kmf.init( ks, password );
			var ctx = createObject( "java", "javax.net.ssl.SSLContext" ).getInstance( "TLS" );
			ctx.init( kmf.getKeyManagers(), javacast( "null", "" ), javacast( "null", "" ) );
			variables.server = ctx.getServerSocketFactory().createServerSocket( javacast( "int", 0 ), javacast( "int", 50 ), inet );
			var params = variables.server.getSSLParameters();
			params.setApplicationProtocols( variables.mode == "tls-h2" ? javacast( "string[]", [ "h2", "http/1.1" ] ) : javacast( "string[]", [ "http/1.1" ] ) );
			variables.server.setSSLParameters( params );
		}
		variables.server.setSoTimeout( javacast( "int", 60000 ) );
		variables.port = variables.server.getLocalPort();
		variables.threadId = replace( createUUID(), "-", "", "all" );

		thread name="h2Accept#variables.threadId#" action="run" {
			_accept();
		}
		return this;
	}

	public numeric function getPort() {
		return variables.port;
	}

	public string function getBaseUrl() {
		return ( variables.plain ? "http" : "https" ) & "://127.0.0.1:#variables.port#";
	}

	/**
	 * the keystore of the server, the certificate is the one to trust (attribute trustStore of cfhttp, password changeit)
	 */
	public string function getTrustStore() {
		return variables.trustStore;
	}

	public numeric function getConnections() {
		return variables.connections;
	}

	/**
	 * the requests the server has got so far, a struct for every request:
	 * protocol ("h2" or "http/1.1"), method, path, authority, scheme, headers (a struct with lower case names), body, connection (the number of the connection)
	 */
	public array function getRequests() {
		lock name="h2server#variables.threadId#" type="exclusive" timeout="10" {
			return duplicate( variables.requests );
		}
	}

	/**
	 * stops the server and returns the recorded requests, an error of the server is thrown here, so a test can not miss it
	 */
	public array function stop() {
		variables.stopped = true;
		try {
			variables.server.close();
		}
		catch ( any e ) {
		}
		for ( var socket in variables.sockets ) {
			try {
				socket.close();
			}
			catch ( any e ) {
			}
		}
		threadJoin( "h2Accept#variables.threadId#", 30000 );
		for ( var name in variables.threads ) {
			threadJoin( name, 30000 );
		}
		if ( len( variables.failure ) ) throw( message="the h2 test server failed: " & variables.failure );
		return variables.requests;
	}

	public void function _accept() {
		try {
			while ( !variables.stopped ) {
				var socket = variables.server.accept();
				variables.connections++;
				var number = variables.connections;
				var name = "h2Conn#variables.threadId#_#number#";
				arrayAppend( variables.sockets, socket );
				arrayAppend( variables.threads, name );
				thread name=name action="run" socket=socket number=number {
					_serve( attributes.socket, attributes.number );
				}
			}
		}
		catch ( any e ) {
			// a server that is stopped ends with an exception of the closed socket
			if ( !variables.stopped ) variables.failure = e.message;
		}
	}

	public void function _serve( required socket, required numeric number ) {
		try {
			arguments.socket.setSoTimeout( javacast( "int", 60000 ) );
			var alpn = "";
			if ( !variables.plain ) {
				arguments.socket.startHandshake();
				alpn = arguments.socket.getApplicationProtocol();
			}
			var is = createObject( "java", "java.io.BufferedInputStream" ).init( arguments.socket.getInputStream() );
			var out = createObject( "java", "java.io.BufferedOutputStream" ).init( arguments.socket.getOutputStream() );
			var scheme = variables.plain ? "http" : "https";

			if ( variables.plain ) {
				// prior knowledge: the HTTP/2 preface, or a plain HTTP/1.1 request
				is.mark( javacast( "int", 8 ) );
				var first = "";
				for ( var i = 1; i <= 4; i++ ) first &= chr( is.read() );
				is.reset();
				if ( first == "PRI " && variables.mode == "h2c" ) alpn = "h2";
			}

			if ( alpn == "h2" ) {
				_serveH2( is, out, arguments.number, scheme );
			}
			else {
				_serveH1( is, out, arguments.number, scheme );
			}
		}
		catch ( eof e ) {
			// the client closed the connection
		}
		catch ( java.io.IOException e ) {
			// the client closed the connection, or the server is stopped
		}
		catch ( any e ) {
			if ( !variables.stopped ) variables.failure = e.message & " " & e.detail;
		}
		finally {
			try {
				arguments.socket.close();
			}
			catch ( any e ) {
			}
		}
	}

	// ---------------------------------------------------------------- HTTP/1.1

	public void function _serveH1( required is, required out, required numeric number, required string scheme ) {
		while ( true ) {
			var head = createObject( "java", "java.io.ByteArrayOutputStream" ).init();
			var last4 = "";
			while ( true ) {
				var b = arguments.is.read();
				if ( b == -1 ) {
					if ( head.size() == 0 ) return;
					throw( type="eof", message="end of the stream" );
				}
				head.write( javacast( "int", b ) );
				last4 = right( last4 & chr( b ), 4 );
				if ( last4 == variables.CRLF & variables.CRLF ) break;
			}
			var lines = listToArray( head.toString( "iso-8859-1" ), variables.CRLF, false, true );
			var req = { "protocol": "http/1.1", "method": listGetAt( lines[ 1 ], 1, " " ), "path": listGetAt( lines[ 1 ], 2, " " ), "authority": "", "scheme": arguments.scheme, "headers": {}, "body": "", "connection": arguments.number };
			for ( var i = 2; i <= arrayLen( lines ); i++ ) {
				req.headers[ lCase( trim( listFirst( lines[ i ], ":" ) ) ) ] = trim( listRest( lines[ i ], ":" ) );
			}
			req.authority = req.headers.host ?: "";
			var length = val( req.headers[ "content-length" ] ?: 0 );
			for ( var i = 1; i <= length; i++ ) req.body &= chr( _read( arguments.is ) );
			_record( req );

			var rsp = _respond( req );
			var text = "HTTP/1.1 #rsp.status# #rsp.reason#" & variables.CRLF & "x-test-server: h1" & variables.CRLF;
			if ( len( rsp.location ) ) text &= "Location: #rsp.location#" & variables.CRLF;
			text &= "Content-Type: text/plain" & variables.CRLF & "Content-Length: #len( rsp.body )#" & variables.CRLF & "Connection: close" & variables.CRLF & variables.CRLF;
			if ( req.method != "HEAD" ) text &= rsp.body;
			arguments.out.write( charsetDecode( text, "iso-8859-1" ) );
			arguments.out.flush();
			return;
		}
	}

	// ---------------------------------------------------------------- HTTP/2

	public void function _serveH2( required is, required out, required numeric number, required string scheme ) {
		var is = arguments.is;
		var out = arguments.out;
		var state = { "dynamic": [], "dynamicSize": 0, "maxDynamic": 4096 };
		var streams = {};
		var continuation = { "stream": 0, "flags": 0, "block": [] };

		// the preface of the client
		var preface = "";
		for ( var i = 1; i <= len( variables.PREFACE ); i++ ) preface &= chr( _read( is ) );
		if ( preface != variables.PREFACE ) throw( message="no HTTP/2 preface: [#preface#]" );
		// our settings (all defaults)
		_writeFrame( out, 4, 0, 0, [] );

		while ( true ) {
			var head = _readBytes( is, 9 );
			var length = head[ 1 ] * 65536 + head[ 2 ] * 256 + head[ 3 ];
			var type = head[ 4 ];
			var flags = head[ 5 ];
			var stream = bitAnd( head[ 6 ], 127 ) * 16777216 + head[ 7 ] * 65536 + head[ 8 ] * 256 + head[ 9 ];
			var payload = _readBytes( is, length );

			switch ( type ) {
				case 4: // SETTINGS
					if ( bitAnd( flags, 1 ) == 0 ) _writeFrame( out, 4, 1, 0, [] );
					break;
				case 6: // PING
					if ( bitAnd( flags, 1 ) == 0 ) _writeFrame( out, 6, 1, 0, payload );
					break;
				case 7: // GOAWAY
					return;
				case 3: // RST_STREAM
					structDelete( streams, stream );
					break;
				case 1: // HEADERS
					var offset = 1;
					var pad = 0;
					if ( bitAnd( flags, 8 ) ) {
						pad = payload[ 1 ];
						offset++;
					}
					if ( bitAnd( flags, 32 ) ) offset += 5;
					var fragment = length - pad - offset + 1 > 0 ? arraySlice( payload, offset, length - pad - offset + 1 ) : [];
					if ( bitAnd( flags, 4 ) ) {
						streams[ stream ] = _newStream( _decodeHeaders( fragment, state ), arguments.number, arguments.scheme );
						if ( bitAnd( flags, 1 ) ) _complete( out, stream, streams );
					}
					else {
						continuation = { "stream": stream, "flags": flags, "block": fragment };
					}
					break;
				case 9: // CONTINUATION
					arrayAppend( continuation.block, payload, true );
					if ( bitAnd( flags, 4 ) ) {
						streams[ stream ] = _newStream( _decodeHeaders( continuation.block, state ), arguments.number, arguments.scheme );
						if ( bitAnd( continuation.flags, 1 ) ) _complete( out, stream, streams );
					}
					break;
				case 0: // DATA
					var offset = 1;
					var pad = 0;
					if ( bitAnd( flags, 8 ) ) {
						pad = payload[ 1 ];
						offset++;
					}
					if ( structKeyExists( streams, stream ) ) {
						for ( var i = offset; i <= length - pad; i++ ) streams[ stream ].req.body &= chr( payload[ i ] );
					}
					// give the window back to the client
					if ( length > 0 ) {
						var inc = [ bitAnd( bitSHRN( length, 24 ), 255 ), bitAnd( bitSHRN( length, 16 ), 255 ), bitAnd( bitSHRN( length, 8 ), 255 ), bitAnd( length, 255 ) ];
						_writeFrame( out, 8, 0, 0, inc );
						if ( !bitAnd( flags, 1 ) ) _writeFrame( out, 8, 0, stream, inc );
					}
					if ( bitAnd( flags, 1 ) && structKeyExists( streams, stream ) ) _complete( out, stream, streams );
					break;
				default: // PRIORITY, WINDOW_UPDATE and the unknown frames are ignored
					break;
			}
		}
	}

	public struct function _newStream( required array headers, required numeric number, required string scheme ) {
		var req = { "protocol": "h2", "method": "", "path": "", "authority": "", "scheme": arguments.scheme, "headers": {}, "body": "", "connection": arguments.number };
		for ( var h in arguments.headers ) {
			switch ( h.name ) {
				case ":method": req.method = h.value; break;
				case ":path": req.path = h.value; break;
				case ":authority": req.authority = h.value; break;
				case ":scheme": req.scheme = h.value; break;
				default: req.headers[ h.name ] = structKeyExists( req.headers, h.name ) ? req.headers[ h.name ] & ", " & h.value : h.value;
			}
		}
		return { "req": req };
	}

	public void function _complete( required out, required numeric stream, required struct streams ) {
		var req = arguments.streams[ arguments.stream ].req;
		structDelete( arguments.streams, arguments.stream );
		_record( req );
		var rsp = _respond( req );

		var block = [];
		// :status (the static table has 200, 204, 206, 304, 400, 404 and 500, the others are literals with the name index 8)
		if ( rsp.status == 200 ) arrayAppend( block, 136 );
		else {
			arrayAppend( block, _encInt( 4, 0, 8 ), true );
			arrayAppend( block, _encString( rsp.status ), true );
		}
		if ( len( rsp.location ) ) {
			arrayAppend( block, _encInt( 4, 0, 46 ), true );
			arrayAppend( block, _encString( rsp.location ), true );
		}
		arrayAppend( block, _encInt( 4, 0, 31 ), true );
		arrayAppend( block, _encString( "text/plain" ), true );
		arrayAppend( block, 0 );
		arrayAppend( block, _encString( "x-test-server" ), true );
		arrayAppend( block, _encString( "h2" ), true );

		var noBody = req.method == "HEAD" || !len( rsp.body );
		_writeFrame( arguments.out, 1, noBody ? 5 : 4, arguments.stream, block );
		if ( !noBody ) {
			var data = [];
			for ( var i = 1; i <= len( rsp.body ); i++ ) arrayAppend( data, asc( mid( rsp.body, i, 1 ) ) );
			_writeFrame( arguments.out, 0, 1, arguments.stream, data );
		}
	}

	public void function _writeFrame( required out, required numeric type, required numeric flags, required numeric stream, required array payload ) {
		var length = arrayLen( arguments.payload );
		var out = arguments.out;
		out.write( javacast( "int", bitAnd( bitSHRN( length, 16 ), 255 ) ) );
		out.write( javacast( "int", bitAnd( bitSHRN( length, 8 ), 255 ) ) );
		out.write( javacast( "int", bitAnd( length, 255 ) ) );
		out.write( javacast( "int", arguments.type ) );
		out.write( javacast( "int", arguments.flags ) );
		out.write( javacast( "int", bitAnd( bitSHRN( arguments.stream, 24 ), 127 ) ) );
		out.write( javacast( "int", bitAnd( bitSHRN( arguments.stream, 16 ), 255 ) ) );
		out.write( javacast( "int", bitAnd( bitSHRN( arguments.stream, 8 ), 255 ) ) );
		out.write( javacast( "int", bitAnd( arguments.stream, 255 ) ) );
		for ( var b in arguments.payload ) out.write( javacast( "int", b ) );
		out.flush();
	}

	// ---------------------------------------------------------------- the answers

	public void function _record( required struct req ) {
		lock name="h2server#variables.threadId#" type="exclusive" timeout="10" {
			arrayAppend( variables.requests, duplicate( arguments.req ) );
		}
	}

	public struct function _respond( required struct req ) {
		var path = listFirst( arguments.req.path, "?" );
		var rsp = { "status": 200, "reason": "OK", "location": "", "body": "ok" };
		if ( path == "/echo" ) {
			var lines = [ "protocol=" & arguments.req.protocol, "method=" & arguments.req.method, "path=" & arguments.req.path, "authority=" & arguments.req.authority, "scheme=" & arguments.req.scheme ];
			for ( var name in listSort( structKeyList( arguments.req.headers ), "text" ) ) arrayAppend( lines, "header." & name & "=" & arguments.req.headers[ name ] );
			arrayAppend( lines, "body=" & arguments.req.body );
			rsp.body = arrayToList( lines, chr( 10 ) );
		}
		else if ( path == "/redirect" ) {
			rsp.status = 302;
			rsp.reason = "Found";
			rsp.location = "/echo";
			rsp.body = "";
		}
		else if ( path == "/slow" ) {
			sleep( 3000 );
		}
		else if ( reFind( "^/status/[0-9]+$", path ) ) {
			rsp.status = listLast( path, "/" );
			rsp.reason = "Status " & rsp.status;
			rsp.body = "status " & rsp.status;
		}
		return rsp;
	}

	// ---------------------------------------------------------------- HPACK (RFC 7541)

	public array function _decodeHeaders( required array block, required struct state ) {
		var headers = [];
		var pos = 1;
		var block = arguments.block;
		var state = arguments.state;
		var count = arrayLen( block );
		while ( pos <= count ) {
			var b = block[ pos ];
			if ( bitAnd( b, 128 ) ) {
				// indexed
				var r = _decInt( block, pos, 7 );
				pos = r.pos;
				arrayAppend( headers, _entry( r.value, state ) );
			}
			else if ( bitAnd( b, 224 ) == 32 ) {
				// dynamic table size update
				var r = _decInt( block, pos, 5 );
				pos = r.pos;
				state.maxDynamic = r.value;
				_evict( state, 0 );
			}
			else {
				// literal: with incremental indexing (01), without indexing (0000) or never indexed (0001)
				var indexed = bitAnd( b, 192 ) == 64;
				var r = _decInt( block, pos, indexed ? 6 : 4 );
				pos = r.pos;
				var name = "";
				if ( r.value > 0 ) name = _entry( r.value, state ).name;
				else {
					var s = _decString( block, pos );
					pos = s.pos;
					name = s.value;
				}
				var s = _decString( block, pos );
				pos = s.pos;
				var header = { "name": name, "value": s.value };
				arrayAppend( headers, header );
				if ( indexed ) {
					var size = len( name ) + len( s.value ) + 32;
					_evict( state, size );
					if ( size <= state.maxDynamic ) {
						arrayPrepend( state.dynamic, header );
						state.dynamicSize += size;
					}
				}
			}
		}
		return headers;
	}

	public struct function _entry( required numeric index, required struct state ) {
		if ( arguments.index < 1 ) throw( message="invalid HPACK index #arguments.index#" );
		if ( arguments.index <= arrayLen( variables.staticTable ) ) return variables.staticTable[ arguments.index ];
		var i = arguments.index - arrayLen( variables.staticTable );
		if ( i > arrayLen( arguments.state.dynamic ) ) throw( message="invalid HPACK index #arguments.index#" );
		return arguments.state.dynamic[ i ];
	}

	public void function _evict( required struct state, required numeric needed ) {
		var state = arguments.state;
		while ( arrayLen( state.dynamic ) && state.dynamicSize + arguments.needed > state.maxDynamic ) {
			var last = state.dynamic[ arrayLen( state.dynamic ) ];
			state.dynamicSize -= len( last.name ) + len( last.value ) + 32;
			arrayDeleteAt( state.dynamic, arrayLen( state.dynamic ) );
		}
	}

	public struct function _decInt( required array block, required numeric pos, required numeric prefix ) {
		var max = 2 ^ arguments.prefix - 1;
		var value = bitAnd( arguments.block[ arguments.pos ], max );
		var pos = arguments.pos + 1;
		if ( value == max ) {
			var m = 0;
			while ( true ) {
				var b = arguments.block[ pos++ ];
				value += bitAnd( b, 127 ) * ( 2 ^ m );
				m += 7;
				if ( !bitAnd( b, 128 ) ) break;
			}
		}
		return { "value": value, "pos": pos };
	}

	public struct function _decString( required array block, required numeric pos ) {
		var huff = bitAnd( arguments.block[ arguments.pos ], 128 ) > 0;
		var r = _decInt( arguments.block, arguments.pos, 7 );
		var text = "";
		if ( huff ) {
			var code = 0;
			var bits = 0;
			for ( var i = r.pos; i < r.pos + r.value; i++ ) {
				var b = arguments.block[ i ];
				for ( var k = 7; k >= 0; k-- ) {
					code = code * 2 + bitAnd( bitSHRN( b, k ), 1 );
					bits++;
					var key = bits & ":" & code;
					if ( structKeyExists( variables.huffman, key ) ) {
						var sym = variables.huffman[ key ];
						if ( sym == 256 ) throw( message="EOS in a huffman encoded string" );
						text &= chr( sym );
						code = 0;
						bits = 0;
					}
				}
			}
		}
		else {
			for ( var i = r.pos; i < r.pos + r.value; i++ ) text &= chr( arguments.block[ i ] );
		}
		return { "value": text, "pos": r.pos + r.value };
	}

	public array function _encInt( required numeric prefix, required numeric flags, required numeric value ) {
		var max = 2 ^ arguments.prefix - 1;
		if ( arguments.value < max ) return [ arguments.flags + arguments.value ];
		var bytes = [ arguments.flags + max ];
		var rest = arguments.value - max;
		while ( rest >= 128 ) {
			arrayAppend( bytes, bitOr( bitAnd( rest, 127 ), 128 ) );
			rest = bitSHRN( rest, 7 );
		}
		arrayAppend( bytes, rest );
		return bytes;
	}

	public array function _encString( required string value ) {
		var bytes = _encInt( 7, 0, len( arguments.value ) );
		for ( var i = 1; i <= len( arguments.value ); i++ ) arrayAppend( bytes, asc( mid( arguments.value, i, 1 ) ) );
		return bytes;
	}

	// ---------------------------------------------------------------- reading

	public numeric function _read( required is ) {
		var b = arguments.is.read();
		if ( b == -1 ) throw( type="eof", message="end of the stream" );
		return b;
	}

	public array function _readBytes( required is, required numeric count ) {
		var bytes = [];
		for ( var i = 1; i <= arguments.count; i++ ) arrayAppend( bytes, _read( arguments.is ) );
		return bytes;
	}
}
