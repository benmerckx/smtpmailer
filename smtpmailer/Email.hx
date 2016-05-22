package smtpmailer;

typedef Email = {
	from: String,
	to: Array<String>,
	subject: String,
	content: {
		?text: String,
		?html: String
	}
}