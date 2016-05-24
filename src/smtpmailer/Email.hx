package smtpmailer;

typedef Email = {
	from: String,
	to: Array<String>,
	subject: String,
	?headers: Map<String, String>,
	content: {
		?text: String,
		?html: String
	},
	?attachments: Array<String>
}