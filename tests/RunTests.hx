package;

import js.node.stream.Readable.IReadable;
import tink.unit.*;
import tink.testrunner.*;
import smtpmailer.*;
import smtpserver.SMTPServer;
import MailParser;

using tink.io.Source;
using tink.CoreApi;

@:asserts
class RunTests {

  static function main() {
    var signalTrigger = Signal.trigger();
    var server = new SMTPServer({
      hideSTARTTLS: true,
      authOptional: true,
      allowInsecureAuth: true,
      onData: (stream, _, cb) -> {
        MailParser.parse(stream).then(
          signalTrigger.trigger,
          err -> trace(err)
        ).then(_ -> cb());
      },
      onAuth: (auth, _, cb) ->
        cb(null, {
          user: auth.username
        })//auth.username == 'test' && auth.password == 'password'
    });
    server.listen(1025, () -> {
      Runner.run(TestBatch.make([
        new RunTests(signalTrigger),
      ])).handle(code -> {
        server.close(() ->
          Runner.exit(code)
        );
      });
    });
  }

  final messages: Signal<ParsedMail>;
  
  function new(messages: Signal<ParsedMail>) {
    this.messages = messages;
  }
  
  public function send() {
    final getMessage = messages.nextTime();
    final email: Email = {
      subject: 'ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠ',
      from: {address: 'mail@example.com', displayName: "It's me, Mario!"},
      to: ['mail@example.com'],
      content: {
        text: 'text content',
        html: '<font color="red">html content</font>'
      },
      attachments: [
        'haxelib.json'
      ]
    }
    return SmtpMailer.connect({
      host: 'localhost',
      port: 1025,
      secure: false,
      auth: {
        username: 'test',
        password: 'password'
      }
    }).next(mailer -> {
      mailer.send(email)
        .next(_ -> getMessage)
        .next(parsed -> {
          asserts.assert(parsed.subject == email.subject);
          asserts.assert(parsed.text == email.content.text);
          asserts.assert(parsed.html == email.content.html);
          asserts.assert(parsed.attachments.length == 1);
          asserts.assert(parsed.attachments[0].filename == 'haxelib.json');
          asserts.assert(haxe.Json.parse(parsed.attachments[0].content.toString()).name == 'smtpmailer');
          mailer.close();
          return asserts.done();
        });
    });
  }
}