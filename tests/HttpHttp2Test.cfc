/**
 * LDEV-6470 the cfhttp attribute httpVersion: "1.1" (the default), "2" (HTTP/2 only, an error if the server can not
 * speak it) and "auto" (HTTP/2 if the server offers it, otherwise HTTP/1.1).
 *
 * The tests run against the HTTP/2 test server in _H2Server.cfc (TLS with ALPN, and plain text HTTP/2 with prior
 * knowledge), which records the requests. What the result says (http_version) is compared with what the server saw.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="http" {

	function run( testResults, testBox ) {

		describe( "HTTP extension: httpVersion, the default is HTTP/1.1", function() {

			it( title="without the attribute the request is HTTP/1.1, also to a server that offers HTTP/2", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h2" );
				try {
					http url="#srv.getBaseUrl()#/echo" trustStore="#srv.getTrustStore()#" timeout=10 result="local.res";
				}
				finally {
					srv.stop();
				}
				expect( res.status_code ).toBe( 200 );
				expect( res.http_version ).toBe( "HTTP/1.1" );
				expect( res.filecontent ).toInclude( "protocol=http/1.1" );
				expect( srv.getRequests()[ 1 ].protocol ).toBe( "http/1.1" );
			});

			it( title="httpVersion=""1.1"" is the same as without the attribute", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h2" );
				try {
					http url="#srv.getBaseUrl()#/echo" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="1.1" result="local.res";
				}
				finally {
					srv.stop();
				}
				expect( res.http_version ).toBe( "HTTP/1.1" );
				expect( srv.getRequests()[ 1 ].protocol ).toBe( "http/1.1" );
			});

			it( title="an invalid value is an error, also with throwOnError=false", body=function( currentSpec ) {
				for ( var throwOnError in [ true, false ] ) {
					var msg = "";
					try {
						http url="http://127.0.0.1:1/" timeout=5 throwOnError=throwOnError httpVersion="3" result="local.res";
					}
					catch ( any e ) {
						msg = e.message;
					}
					expect( msg ).toInclude( "invalid value for attribute httpVersion [3]" );
					expect( msg ).toInclude( "1.1, 2, auto" );
				}
			});

		});

		describe( "HTTP extension: httpVersion=""2""", function() {

			it( title="a GET goes over HTTP/2 with TLS (ALPN), and the result says so", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h2" );
				try {
					http url="#srv.getBaseUrl()#/echo?a=1&b=two" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="2" result="local.res" {
						httpparam type="header" name="X-Test" value="from cfhttp";
					}
				}
				finally {
					srv.stop();
				}
				expect( res.status_code ).toBe( 200 );
				expect( res.http_version ).toBe( "HTTP/2.0" );
				expect( res.header ).toInclude( "HTTP/2.0 200" );
				expect( res.status_text ).toBe( "OK" );
				expect( res.mimetype ).toBe( "text/plain" );
				expect( res.responseheader[ "x-test-server" ] ).toBe( "h2" );

				// what the server saw
				var reqs = srv.getRequests();
				expect( reqs ).toHaveLength( 1 );
				expect( reqs[ 1 ].protocol ).toBe( "h2" );
				expect( reqs[ 1 ].method ).toBe( "GET" );
				expect( reqs[ 1 ].path ).toBe( "/echo?a=1&b=two" );
				expect( reqs[ 1 ].authority ).toBe( "127.0.0.1:#srv.getPort()#" );
				expect( reqs[ 1 ].scheme ).toBe( "https" );
				expect( reqs[ 1 ].headers[ "x-test" ] ).toBe( "from cfhttp" );
				expect( res.filecontent ).toInclude( "protocol=h2" );
				expect( res.filecontent ).toInclude( "header.x-test=from cfhttp" );
			});

			it( title="a POST sends its body and the content type over HTTP/2", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h2" );
				try {
					http url="#srv.getBaseUrl()#/echo" method="post" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="2" result="local.res" {
						httpparam type="header" name="Content-Type" value="text/plain; charset=utf-8";
						httpparam type="body" value="hello http2";
					}
				}
				finally {
					srv.stop();
				}
				expect( res.status_code ).toBe( 200 );
				expect( res.http_version ).toBe( "HTTP/2.0" );
				var reqs = srv.getRequests();
				expect( reqs[ 1 ].method ).toBe( "POST" );
				expect( reqs[ 1 ].body ).toBe( "hello http2" );
				expect( reqs[ 1 ].headers[ "content-type" ] ).toInclude( "text/plain" );
				expect( res.filecontent ).toInclude( "body=hello http2" );
			});

			it( title="form fields are sent over HTTP/2", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h2" );
				try {
					http url="#srv.getBaseUrl()#/echo" method="post" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="2" result="local.res" {
						httpparam type="formfield" name="name" value="Lucee";
						httpparam type="formfield" name="kind" value="a b";
					}
				}
				finally {
					srv.stop();
				}
				var reqs = srv.getRequests();
				expect( reqs[ 1 ].protocol ).toBe( "h2" );
				expect( reqs[ 1 ].headers[ "content-type" ] ).toInclude( "application/x-www-form-urlencoded" );
				expect( reqs[ 1 ].body ).toInclude( "name=Lucee" );
				expect( reqs[ 1 ].body ).toInclude( "kind=a+b" );
			});

			it( title="a HEAD request has no body", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h2" );
				try {
					http url="#srv.getBaseUrl()#/echo" method="head" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="2" throwOnError=true result="local.res";
				}
				finally {
					srv.stop();
				}
				expect( res.status_code ).toBe( 200 );
				expect( res.http_version ).toBe( "HTTP/2.0" );
				expect( res.filecontent ).toBeEmpty();
			});

			it( title="the requests to a host use one connection, and the result says that the second one was reused", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h2" );
				try {
					http url="#srv.getBaseUrl()#/echo?n=1" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="2" result="local.first";
					http url="#srv.getBaseUrl()#/echo?n=2" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="2" result="local.second";
					http url="#srv.getBaseUrl()#/echo?n=3" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="2" result="local.third";
				}
				finally {
					srv.stop();
				}
				// the headers of the later requests come from the dynamic table of HPACK of the connection
				expect( first.filecontent ).toInclude( "path=/echo?n=1" );
				expect( second.filecontent ).toInclude( "path=/echo?n=2" );
				expect( third.filecontent ).toInclude( "path=/echo?n=3" );
				expect( third.http_version ).toBe( "HTTP/2.0" );
				expect( srv.getConnections() ).toBe( 1 );
				expect( srv.getRequests() ).toHaveLength( 3 );
				expect( first.connection.reused ).toBeFalse();
				expect( second.connection.reused ).toBeTrue();
				expect( third.connection.reused ).toBeTrue();
				expect( third.connection.pooled ).toBeTrue();
			});

			it( title="without pooling every request has its own connection", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h2" );
				try {
					http url="#srv.getBaseUrl()#/echo?n=1" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="2" pooling=false result="local.first";
					http url="#srv.getBaseUrl()#/echo?n=2" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="2" pooling=false result="local.second";
				}
				finally {
					srv.stop();
				}
				expect( first.http_version ).toBe( "HTTP/2.0" );
				expect( second.http_version ).toBe( "HTTP/2.0" );
				expect( srv.getConnections() ).toBe( 2 );
				expect( first.connection.pooled ).toBeFalse();
			});

			it( title="a redirect is followed over HTTP/2", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h2" );
				try {
					http url="#srv.getBaseUrl()#/redirect" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="2" throwOnError=true result="local.res";
				}
				finally {
					srv.stop();
				}
				expect( res.status_code ).toBe( 200 );
				expect( res.http_version ).toBe( "HTTP/2.0" );
				expect( res.filecontent ).toInclude( "path=/echo" );
				var reqs = srv.getRequests();
				expect( reqs ).toHaveLength( 2 );
				expect( reqs[ 1 ].path ).toBe( "/redirect" );
				expect( reqs[ 2 ].path ).toBe( "/echo" );
				expect( reqs[ 2 ].protocol ).toBe( "h2" );
			});

			it( title="a status of the server that is an error is an error of the tag, with throwOnError=false it is the result", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h2" );
				try {
					http url="#srv.getBaseUrl()#/status/404" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="2" throwOnError=false result="local.res";
					expect( res.status_code ).toBe( 404 );
					expect( res.http_version ).toBe( "HTTP/2.0" );
					expect( res.filecontent ).toBe( "status 404" );
					// HTTP/2 has no reason phrase, the standard one is used
					expect( res.status_text ).toBe( "Not Found" );

					var msg = "";
					try {
						http url="#srv.getBaseUrl()#/status/404" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="2" throwOnError=true result="local.res2";
					}
					catch ( any e ) {
						msg = e.message;
					}
					expect( msg ).toInclude( "404" );
				}
				finally {
					srv.stop();
				}
			});

			it( title="HTTP/2 without TLS (h2c with prior knowledge) works with a server that speaks it", body=function( currentSpec ) {
				var srv = new _H2Server( "h2c" );
				try {
					http url="#srv.getBaseUrl()#/echo" timeout=10 httpVersion="2" throwOnError=true result="local.res";
				}
				finally {
					srv.stop();
				}
				expect( res.status_code ).toBe( 200 );
				expect( res.http_version ).toBe( "HTTP/2.0" );
				var reqs = srv.getRequests();
				expect( reqs[ 1 ].protocol ).toBe( "h2" );
				expect( reqs[ 1 ].scheme ).toBe( "http" );
			});

			it( title="the timeout is an error when the server does not answer in time", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h2" );
				var msg = "";
				try {
					http url="#srv.getBaseUrl()#/slow" trustStore="#srv.getTrustStore()#" timeout=1 httpVersion="2" throwOnError=true result="local.res";
				}
				catch ( any e ) {
					msg = e.message;
				}
				finally {
					srv.stop();
				}
				expect( msg ).notToBeEmpty( "the request must run into the timeout" );
				expect( msg ).toInclude( "408" );
			});

		});

		describe( "HTTP extension: httpVersion=""2"" with a server that can not speak HTTP/2 is an error, there is no fallback", function() {

			it( title="a TLS server without h2 in ALPN: error", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h1" );
				var msg = "";
				try {
					http url="#srv.getBaseUrl()#/echo" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="2" throwOnError=true result="local.res";
				}
				catch ( any e ) {
					msg = e.message;
				}
				finally {
					srv.stop();
				}
				expect( msg ).notToBeEmpty( "httpVersion=2 against a server that does not speak HTTP/2 must be an error" );
				// nothing was sent with HTTP/1.1
				expect( srv.getRequests() ).toBeEmpty();
			});

			it( title="a plain HTTP/1.1 server: error", body=function( currentSpec ) {
				var srv = new _H2Server( "h1" );
				var msg = "";
				try {
					http url="#srv.getBaseUrl()#/echo" timeout=10 httpVersion="2" throwOnError=true result="local.res";
				}
				catch ( any e ) {
					msg = e.message;
				}
				finally {
					srv.stop();
				}
				expect( msg ).notToBeEmpty( "httpVersion=2 against a HTTP/1.1 server must be an error" );
			});

			it( title="without throwOnError the failure is the usual error result, never a response", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h1" );
				var res = "";
				try {
					http url="#srv.getBaseUrl()#/echo" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="2" throwOnError=false result="res";
				}
				finally {
					srv.stop();
				}
				expect( res.error ).toBeTrue( "the result must flag the error" );
				expect( res.status_code ).toBe( 0 );
				expect( res.errordetail ).notToBeEmpty( "the cause must be in the result" );
				expect( srv.getRequests() ).toBeEmpty( "no request was sent with HTTP/1.1" );
			});

		});

		describe( "HTTP extension: httpVersion=""auto""", function() {

			it( title="uses HTTP/2 with a server that offers it", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h2" );
				try {
					http url="#srv.getBaseUrl()#/echo" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="auto" result="local.res";
				}
				finally {
					srv.stop();
				}
				expect( res.status_code ).toBe( 200 );
				expect( res.http_version ).toBe( "HTTP/2.0" );
				expect( srv.getRequests()[ 1 ].protocol ).toBe( "h2" );
			});

			it( title="falls back to HTTP/1.1 with a TLS server that does not offer HTTP/2, and the result says so", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h1" );
				try {
					http url="#srv.getBaseUrl()#/echo" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="auto" result="local.res";
				}
				finally {
					srv.stop();
				}
				expect( res.status_code ).toBe( 200 );
				expect( res.http_version ).toBe( "HTTP/1.1" );
				expect( res.filecontent ).toInclude( "protocol=http/1.1" );
				expect( srv.getRequests()[ 1 ].protocol ).toBe( "http/1.1" );
			});

			it( title="is HTTP/1.1 without TLS (there is no negotiation without TLS)", body=function( currentSpec ) {
				var srv = new _H2Server( "h2c" );
				try {
					http url="#srv.getBaseUrl()#/echo" timeout=10 httpVersion="auto" result="local.res";
				}
				finally {
					srv.stop();
				}
				expect( res.status_code ).toBe( 200 );
				expect( res.http_version ).toBe( "HTTP/1.1" );
				expect( srv.getRequests()[ 1 ].protocol ).toBe( "http/1.1" );
			});

			it( title="an error of the server is a status of the result, like with HTTP/1.1", body=function( currentSpec ) {
				var srv = new _H2Server( "tls-h1" );
				try {
					http url="#srv.getBaseUrl()#/status/500" trustStore="#srv.getTrustStore()#" timeout=10 httpVersion="auto" throwOnError=false result="local.res";
				}
				finally {
					srv.stop();
				}
				expect( res.status_code ).toBe( 500 );
				expect( res.http_version ).toBe( "HTTP/1.1" );
			});

		});
	}
}
