package smtpmailer;

typedef Email = {
	from: Address,
	to: Array<Address>,
	subject: String,
	?headers: Map<String, String>,
	content: {
		?text: String,
		?html: String
	},
	?attachments: Array<String>
}