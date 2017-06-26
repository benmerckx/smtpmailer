# smtpmailer

Runs on sys targets and nodejs.

#### SSL/StartTls:
- Supported on java/php/nodejs
- Supported on haxe 3.2 neko/cpp with `-lib hxssl`
- Supported on haxe 3.3+ neko/cpp (using native sys.ssl.Socket)

```haxe
var mailer = new SmtpMailer({
	host: 'hostname',
	port: 587,
	auth: {
		username: 'user',
		password: 'pass'
	}
});
mailer.send({
	subject: 'Subject',
	from: { address: 'mail@example.com', displayName: 'It\s me, Mario!' },
	to: ['mail@example.com'],
	content: {
		text: 'hello',
		html: '<font color="red">hello</font>'
	},
	attachments: ['image.png']
}).handle(function(res) {
	switch res {
		case Success(_):
			trace('Email sent!');
		case Failure(e): {
			trace('Something went wrong: '+e);
		}
	}
});
```
