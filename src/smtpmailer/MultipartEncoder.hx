package smtpmailer;

import tink.io.Transformer;
import haxe.crypto.Base64;
import tink.Chunk;
import haxe.io.Path;
import tink.multipart.Multipart;
import tink.multipart.Part;
import tink.http.Header;
import mime.Mime;
import mtwin.mail.Tools;

using tink.io.Source;
using tink.CoreApi;

class Base64Encoder implements Transformer<Error, Error> {
	final lineLength: Int;
	final separator: String;

	public function new(lineLength, separator) {
		this.lineLength = lineLength;
		this.separator = separator;
	}

	public function transform(source: RealSource): RealSource {
		var offset = 0, remaining = Chunk.EMPTY;
		function encode(chunk: Chunk) {
			final res = new StringBuf();
			final encoded = Base64.encode(chunk);
			final total = encoded.length;
			var i = 0;
			while (i < total) {
				final length = Std.int(Math.min(
					lineLength - offset,
					total - i
				));
				res.addSub(encoded, i, length);
				i += length;
				offset = (offset + i) % lineLength;
				if (offset == 0) res.add(separator);
			}
			return res.toString();
		}
		return (source.chunked().map(function (chunk: Chunk): Chunk {
			final part = remaining.concat(chunk);
			remaining = part.slice(part.length - part.length % 3, part.length);
			return encode(part.slice(0, part.length - remaining.length));
		}): RealSource).append(
			(Future.lazy(() -> (encode(remaining): IdealSource)): IdealSource)
		).append(separator);
	}
}

class MultipartEncoder {
	static inline final NEWLINE = '\n\r';
	static var base64encode = new Base64Encoder(76, NEWLINE);

	static function maybe<T>(value: Null<T>)
		return switch value {
			case null: None;
			case v: Some(v);
		}

	static function part(headers: Map<String, String>, content: IdealSource)
		return new Part(
			new Header([for (name => value in headers)
				new HeaderField(name, value)
			]), 
			content
		);

	static function quotedPart(contentType: String, content: String)
		return part([
				'content-type' => contentType,
				'content-transfer-encoding' => 'quoted-printable'
			], 
			Tools.encodeQuotedPrintable(content)
		);

	public static function encode(email: Email): IdealSource {
		final text = maybe(email.content.text).map(v ->
			quotedPart('text/plain; charset=utf-8', v)
		);
		final html = maybe(email.content.html).map(v ->
			quotedPart('text/html; charset=utf-8', v)
		);
		final content = switch [text, html] {
			case [Some(t), None]: t;
			case [None, Some(h)]: h;
			case [Some(t), Some(h)]:
				final alternative = new Multipart([t, h]);
				part([
					'content-type' => 
						alternative.getContentTypeHeader('alternative').value
				], alternative.toIdealSource());
			default: throw 'No content (text or html)';
		}

		final parts = switch email.attachments {
			case null: [content];
			case attachments:
				[content].concat(
					attachments.map(file -> {
						final type = switch Mime.lookup(file) {
							case null: 'application/octet-stream';
							case mime: mime;
						}
						final contentType = switch Mime.db.get(type) {
							case {charset: c} if (c != null): '$type; charset=$c';
							default: type;
						}
						final name = Path.withoutDirectory(file);
						final ideal = (stream: RealSource) -> stream.idealize(err -> ''); // What to do here?
						return part([
							'content-type' => contentType,
							'content-disposition' => 'attachment; filename="$name"',
							'content-transfer-encoding' => 'base64'
						], ideal(
							asys.io.File
								.readStream(file)
								.transform(base64encode)
						));
					})
				);
		}

		final multipart = new Multipart(parts);
		final headers = new Header([
			new HeaderField('from', '${email.from}'),
			new HeaderField('to', email.to.map(to -> '${to}').join(',')),
			new HeaderField('subject', email.subject)
		].concat(switch email.headers {
			case null: [];
			case headers: [
				for (key => value in headers)
					new HeaderField(key, value)
			];
		}).concat([
			new HeaderField('mime-version', '1.0'),
			multipart.getContentTypeHeader()
		]));

		return (headers.toString(): IdealSource)
			.append(multipart);
	}

}