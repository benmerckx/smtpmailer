package smtpmailer;

import asys.net.Socket;
import asys.net.Host;
import asys.ssl.Socket as SslSocket;
import haxe.io.Bytes;
import haxe.io.Error;
import haxe.io.BytesOutput;
import haxe.crypto.Base64;
import tink.io.Sink;
import tink.io.StreamParser;

using tink.io.Source;
using tink.CoreApi;

typedef Credentials = {
	username: String,
	password: String
}

typedef ConnectionOptions = {
	host:String,
	port:Int,
	?secure:Bool,
	?auth: Credentials
}

@:nullSafety
class SmtpMailer {
	static inline final NEW_LINE = "\r\n";
	static final parser = new Splitter(NEW_LINE);
	var input: RealSource;
	final output: RealSink;
	public final close: () -> Void;

	public function new(
		input: RealSource,
		output: RealSink,
		close: () -> Void
	) {
		this.input = input;
		this.output = output;
		this.close = close;
	}
		
	static function hasCode(line: String, code: Int) {
		final str = '$code';
		return line.substr(0, str.length) == str;
	}

	static function hasOption(options: Array<String>, search: String) {
		for (option in options)
			if (option.toLowerCase().indexOf(search) > -1)
				return true;
		return false;
	}

	function readLine(expectedStatus: Int): Promise<String>
		return input.parse(parser).next(response -> {
			input = response.b;
			final line = response.a.force().toString();
			return if (hasCode(line, expectedStatus)) line else new Error(line);
		});
	
	function writeLine(line: String): Promise<Noise> {
		return ((line+NEW_LINE): IdealSource).pipeTo(output)
			.next(res -> switch res {
				case AllWritten: Noise;
				case e: new Error('Could not write to sink: $e');
			});
	}

	function handshake(): Promise<Array<String>>
		return readLine(220)
			.next(_ -> writeLine('EHLO ' + Host.localhost()))
			.next(_ -> {
				var options = [];
				return Promise.iterate({
					iterator: () -> {
						next: () -> readLine(250),
						hasNext: () -> true
					}
				}, (option: String) -> {
					options.push(option);
					return if (option.substr(3, 1) != '-') Some(options) else None;
				}, []);
			});

	function auth(credentials: Credentials)
		return writeLine('AUTH LOGIN')
			.next(_ -> readLine(334))
			.next(_ -> writeLine(Base64.encode(Bytes.ofString(credentials.username))))
			.next(_ -> readLine(334))
			.next(_ -> writeLine(Base64.encode(Bytes.ofString(credentials.password))))
			.next(_ -> readLine(235))
			.noise();

	public function send(email: Email) {
		return writeLine('MAIL from: ${email.from.address}')
			.next(_ -> readLine(250))
			.next(_ -> Promise.inSequence(
				email.to.map(user ->
					writeLine('RCPT to: ${user.address}')
						.next(_ -> readLine(250))
				)
			))
			.next(_ -> writeLine('DATA'))
			.next(_ -> readLine(354))
			.next(_ -> 
				MultipartEncoder.encode(email)
				.append(NEW_LINE + '.' + NEW_LINE)
				.pipeTo(output)
			)
			.next(res -> switch res {
				case AllWritten: Noise;
				case SinkFailed(e, _): e;
				default: new Error('Connection ended');
			})
			.next(_ -> readLine(250))
			.noise();
	}

	public static function connect(connection: ConnectionOptions): Promise<SmtpMailer> {
		function toMailer(socket: Socket): SmtpMailer
			return new SmtpMailer(socket.input, socket.output, socket.close);
		function connect(socket: Socket): Promise<SmtpMailer> 
			return socket
				.connect(new Host(connection.host), connection.port)
				.next(_ -> toMailer(socket));
		function upgradeTls(socket: Socket, mailer: SmtpMailer): Promise<SmtpMailer>
			return mailer.writeLine('STARTTLS')
				.next(_ -> mailer.readLine(220))
				.next(_ -> {
					final upgraded = toMailer(SslSocket.upgrade(socket));
					return upgraded.writeLine('EHLO ' + Host.localhost())
						.next(_ -> upgraded);
				});
		function auth(mailer: SmtpMailer, options: Array<String>): Promise<SmtpMailer>
			return switch connection.auth {
				case null: mailer;
				case c: mailer.auth(c).next(_ -> mailer);
			}
		return switch connection {
			case {secure: true} | {secure: null, port: 465}:
				connect(new SslSocket())
					.next(mailer -> mailer.handshake().next(auth.bind(mailer)));
			default:
				final socket = new Socket();
				connect(socket)
					.next(mailer ->
						mailer.handshake().next(options ->
							if (hasOption(options, 'starttls'))
								upgradeTls(socket, mailer).next(mailer -> auth(mailer, options));
							else auth(mailer, options)
						)
					);
		}
	}
}