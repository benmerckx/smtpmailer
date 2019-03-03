package;

import tink.unit.*;
import tink.testrunner.*;
import smtpmailer.*;
import smtpserver.SMTPServer;

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
        final source = Source.ofNodeStream('mail', stream);
        source.all().handle(res -> {
          signalTrigger.trigger(res.sure().toString());
          cb();
        });
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

  final messages: Signal<String>;
  
  function new(messages: Signal<String>) {
    this.messages = messages;
  }
  
  public function send() {
    final getMessage = messages.nextTime();
    return SmtpMailer.connect({
      host: 'localhost',
      port: 1025,
      secure: false,
      auth: {
        username: 'test',
        password: 'password'
      }
    }).next(mailer -> {
      mailer.send({
        subject: 'Subject',
        from: {address: '<mail@example.com>', displayName: "It's me, Mario!"},
        to: ['mail@example.com'],
        content: {
          text: 'hello',
          html: '<font color="red">hello</font>'
        },
        attachments: []
      })
      .next(_ -> getMessage)
      .next(message -> {
        trace(message);
        mailer.close();
        return asserts.done();
      });
    });
    /*mailer.send({
      subject: 'Subject',
      from: { address: 'mail@example.com', displayName: "It's me, Mario!" },
      to: ['mail@example.com'],
      content: {
        text: 'hello',
        html: '<font color="red">hello</font>'
      },
      attachments: []
    }).handle(function(o) {
      var result = switch o {
        case Success(_): Success(Noise);
        case Failure(e): Failure(Error.withData('Error', e));
      }
			asserts.assert(result);
			asserts.done();
		});*/
  }
}