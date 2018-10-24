package;

import tink.unit.*;
import tink.testrunner.*;
import smtpmailer.*;

using tink.CoreApi;

@:asserts
class RunTests {

  static function main() {
    
    Runner.run(TestBatch.make([
      new RunTests(),
    ])).handle(Runner.exit);
  }
  
  function new() {}
  
  public function send() {
    var mailer = new SmtpMailer({
      host: 'localhost',
      port: 1025,
    });
    mailer.send({
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
		});
    
    return asserts;
  }
}