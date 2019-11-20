# smtpmailer

Runs on sys targets and nodejs. Requires haxe 4+

```haxe
final email = {
	subject: 'Subject',
	from: {address: 'mail@example.com', displayName: "It's me, Mario!"},
	to: ['mail@example.com'],
	content: {
		text: 'hello',
		html: '<font color="red">hello</font>'
	},
	attachments: ['image.png']
}

smtpmailer.SmtpMailer.connect({
	host: 'hostname',
	port: 587,
	auth: {
		username: 'user',
		password: 'pass'
	}
}).next(mailer ->
  mailer.send(email).next(
    _ -> mailer.close()
  );
).handle(function(res) {
	switch res {
		case Success(_):
			trace('Email sent!');
		case Failure(e): {
			trace('Something went wrong: '+e);
		}
	}
});
```
