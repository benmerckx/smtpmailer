package smtpmailer;

import mtwin.mail.Part;
import mime.Mime;

class MultipartEncoder {

	public static function encode(email: Email): String {
		var main: Part;
		var content: Part;

		if (email.content.html == null) {
			content = new Part('text/plain', 'utf-8');
			content.setContent(email.content.text);
		} else {
			content = new Part('multipart/alternative', 'utf-8');
			if (email.content.text != null)
				content.newPart('text/plain').setContent(email.content.text);
			if (email.content.html != null)
				content.newPart('text/html').setContent(email.content.html);
		}

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
		}

		main.setHeader('From', '"${email.from.displayName}" <${email.from.address}>');
		main.setHeader('To', email.to.map(function(to) return '"${to.displayName}" <${to.address}>').join(','));
		main.setHeader('Subject', email.subject);
		if (email.headers != null)
			for (key in email.headers.keys())
				main.setHeader(key, email.headers.get(key));

		return main.get();
	}

}