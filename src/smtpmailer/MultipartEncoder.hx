package smtpmailer;

import tink.io.Source.IdealSource;
import tink.multipart.Multipart;
import tink.multipart.Part;
import tink.http.Header;
import mime.Mime;
import mtwin.mail.Tools;

class MultipartEncoder {

	public static function encode(email: Email): IdealSource {
		var parts = [];

		if (email.content.text != null)
			parts.push(new Part(
				new Header([
					new HeaderField(CONTENT_TYPE, 'text/plain; charset=utf-8'),
					new HeaderField('Content-transfer-encoding', 'quoted-printable')
				]), 
				Tools.encodeQuotedPrintable(email.content.text)
			));
		if (email.content.html != null)
			parts.push(new Part(
				new Header([
					new HeaderField(CONTENT_TYPE, 'text/html; charset=utf-8'),
					new HeaderField('Content-transfer-encoding', 'quoted-printable')
				]), 
				Tools.encodeQuotedPrintable(email.content.html)
			));
		
		/*
		if (email.attachments != null) {
			main = new Part('multipart/mixed');
			main.addPart(content);
			for(file in email.attachments) {
				var type = Mime.lookup(file);
				if (type == null) type = 'application/octet-stream';
				var part = main.newPart(type);
				part.setContentFromFile(file, type);
			}
		} else {
			main = content;
		}*/

		final multipart = new Multipart(parts);
		final headers = new Header([
			new HeaderField('From', email.from.format()),
			new HeaderField('To', email.to.map(to -> to.format()).join(',')),
			new HeaderField('Subject', email.subject)
		].concat(
			if (email.headers == null) []
			else [
				for (key => value in email.headers)
					new HeaderField(key, value)
			]
		).concat([
			new HeaderField('MIME-Version', '1.0'),
			multipart.getContentTypeHeader()
		]));

		return (headers.toString(): IdealSource)
			.append(multipart);
	}

}