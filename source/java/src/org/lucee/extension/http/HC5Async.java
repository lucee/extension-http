package org.lucee.extension.http;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.net.URI;
import java.nio.ByteBuffer;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicReference;

import org.apache.hc.client5.http.impl.async.CloseableHttpAsyncClient;
import org.apache.hc.client5.http.protocol.HttpClientContext;
import org.apache.hc.core5.concurrent.FutureCallback;
import org.apache.hc.core5.http.ClassicHttpResponse;
import org.apache.hc.core5.http.ContentType;
import org.apache.hc.core5.http.EntityDetails;
import org.apache.hc.core5.http.HttpEntity;
import org.apache.hc.core5.http.HttpException;
import org.apache.hc.core5.http.HttpResponse;
import org.apache.hc.core5.http.impl.EnglishReasonPhraseCatalog;
import org.apache.hc.core5.http.io.entity.ByteArrayEntity;
import org.apache.hc.core5.http.message.BasicClassicHttpResponse;
import org.apache.hc.core5.http.message.BasicHttpRequest;
import org.apache.hc.core5.http.nio.AsyncEntityConsumer;
import org.apache.hc.core5.http.nio.AsyncEntityProducer;
import org.apache.hc.core5.http.nio.CapacityChannel;
import org.apache.hc.core5.http.nio.entity.BasicAsyncEntityConsumer;
import org.apache.hc.core5.http.nio.entity.BasicAsyncEntityProducer;
import org.apache.hc.core5.http.nio.support.BasicRequestProducer;
import org.apache.hc.core5.http.nio.support.BasicResponseConsumer;
import org.apache.hc.core5.http.Message;

import lucee.commons.net.http.HTTPRequest;
import lucee.commons.net.http.Header;

/**
 * Sends a request with the asynchronous client of Apache HttpClient 5, that is the client that speaks HTTP/2
 * (httpVersion="2" or "auto", LDEV-6470). The request and the response are exchanged in memory (the body of the
 * request is buffered before it is sent, the body of the response before the response is returned), the response is
 * returned as a classic response, so the rest of the engine (redirects, the result of the tag) is the same for
 * both clients.
 */
final class HC5Async {

	private HC5Async() {
	}

	/**
	 * the consumer of the body of a response, it also keeps the content encoding of the body: the client removes it
	 * when it has decompressed the body
	 */
	private static final class BodyConsumer implements AsyncEntityConsumer<byte[]> {

		private final BasicAsyncEntityConsumer delegate = new BasicAsyncEntityConsumer();
		volatile String encoding;

		@Override
		public void streamStart(EntityDetails entityDetails, FutureCallback<byte[]> resultCallback) throws HttpException, IOException {
			encoding = entityDetails.getContentEncoding();
			delegate.streamStart(entityDetails, resultCallback);
		}

		@Override
		public void failed(Exception cause) {
			delegate.failed(cause);
		}

		@Override
		public byte[] getContent() {
			return delegate.getContent();
		}

		@Override
		public void updateCapacity(CapacityChannel capacityChannel) throws IOException {
			delegate.updateCapacity(capacityChannel);
		}

		@Override
		public void consume(ByteBuffer src) throws IOException {
			delegate.consume(src);
		}

		@Override
		public void streamEnd(List<? extends org.apache.hc.core5.http.Header> trailers) throws HttpException, IOException {
			delegate.streamEnd(trailers);
		}

		@Override
		public void releaseResources() {
			delegate.releaseResources();
		}
	}

	/**
	 * the body of the request in memory, the content type is kept
	 */
	static HttpEntity buffer(HttpEntity entity) throws IOException {
		if (entity == null) return null;
		ByteArrayOutputStream baos = new ByteArrayOutputStream();
		entity.writeTo(baos);
		String ct = entity.getContentType();
		return new ByteArrayEntity(baos.toByteArray(), ct == null ? null : ContentType.parse(ct));
	}

	/**
	 * sends the request and waits for the response
	 * 
	 * @param entity the body of the request, already in memory (see buffer)
	 * @param canceller receives the action that cancels the request
	 */
	static ClassicHttpResponse execute(CloseableHttpAsyncClient client, String method, URI uri, HTTPRequest r, HttpEntity entity, HttpClientContext context,
			AtomicReference<Runnable> canceller) throws IOException {
		BasicHttpRequest request = new BasicHttpRequest(method, uri);
		for (Header h: r.getHeaders()) {
			// the length comes from the body
			if ("content-length".equalsIgnoreCase(h.getName())) continue;
			request.addHeader(h.getName(), h.getValue());
		}

		AsyncEntityProducer producer = null;
		if (entity != null) {
			String ct = entity.getContentType();
			producer = new BasicAsyncEntityProducer(entity.getContent().readAllBytes(), ct == null ? null : ContentType.parse(ct));
		}

		BodyConsumer consumer = new BodyConsumer();
		Future<Message<HttpResponse, byte[]>> future = client.execute(new BasicRequestProducer(request, producer), new BasicResponseConsumer<>(consumer), null, context, null);
		canceller.set(() -> future.cancel(true));
		if (r.isAborted()) future.cancel(true);

		Message<HttpResponse, byte[]> message;
		try {
			message = future.get();
		}
		catch (InterruptedException e) {
			future.cancel(true);
			Thread.currentThread().interrupt();
			InterruptedIOException ioe = new InterruptedIOException("the request was interrupted");
			ioe.initCause(e);
			throw ioe;
		}
		catch (CancellationException e) {
			IOException ioe = new IOException("the request was aborted");
			ioe.initCause(e);
			throw ioe;
		}
		catch (ExecutionException e) {
			Throwable cause = e.getCause() == null ? e : e.getCause();
			if (cause instanceof IOException) throw (IOException) cause;
			if (cause instanceof RuntimeException) throw (RuntimeException) cause;
			// a violation of the protocol (HttpException, for example an HTTP/2 error) is an IOException for the caller
			throw new IOException(cause.getMessage() == null ? cause.toString() : cause.getMessage(), cause);
		}
		return toClassic(message.getHead(), message.getBody(), consumer.encoding);
	}

	private static ClassicHttpResponse toClassic(HttpResponse head, byte[] body, String encoding) {
		// HTTP/2 has no reason phrase, the result of the tag has one for every version of the protocol
		String reason = head.getReasonPhrase();
		if (reason == null) reason = EnglishReasonPhraseCatalog.INSTANCE.getReason(head.getCode(), Locale.ENGLISH);
		BasicClassicHttpResponse rsp = new BasicClassicHttpResponse(head.getCode(), reason);
		rsp.setVersion(head.getVersion());
		for (org.apache.hc.core5.http.Header h: head.getHeaders()) {
			rsp.addHeader(h);
		}
		if (body != null) {
			String ct = rsp.getFirstHeader("Content-Type") == null ? null : rsp.getFirstHeader("Content-Type").getValue();
			rsp.setEntity(new ByteArrayEntity(body, ct == null ? null : ContentType.parseLenient(ct), encoding));
		}
		return rsp;
	}
}
