typedef Address = {
	value: Array<{
		name: String,
		address: String,
	}>
}

typedef ParsedMail = {
	headers: Map<String, String>,
	subject: String,
	from: Address,
	to: Address,
	cc: Address,
	bcc: Address,
	date: Date,
	messageId: String,
	inReplyTo: String,
	//'reply-to': Address,
	references: Array<String>,
	html: String,
	text: String,
	textAsHtml: String,
	attachments: Array<Dynamic>
}

typedef Attachment = {
	filename: String,
	contentType: String,
	contentDisposition: String,
	checksum: String,
	size: Int,
	headers: Map<String, String>,
	content: js.node.buffer.Buffer,
	contentId: String,
	cid: String,
	related: Bool
}

@:jsRequire('mailparser')
extern class MailParser {
	@:native('simpleParser')
	public static function parse(source: String): js.Promise<ParsedMail>;
}