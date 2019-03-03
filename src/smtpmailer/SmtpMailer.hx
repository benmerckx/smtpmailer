package smtpmailer;

import asys.net.Socket;
import asys.net.Host;
import asys.ssl.Socket as SslSocket;
import haxe.io.Bytes;
import haxe.io.Error;
import haxe.io.BytesOutput;
import haxe.crypto.Base64;
import tink.io.Sink;

using tink.io.Source;
using tink.CoreApi;

typedef ConnectionOptions = {
	host:String,
	port:Int,
	?secure:Bool,
	?auth:{
		username:String,
		password:String
	}
}

@:nullSafety
class SmtpMailer {
	static final parser = new LineParser();
	var input: RealSource;
	final output: RealSink;
	final close: () -> Void;

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

	function readLine(expectedStatus: Int): Promise<String>
		return input.parse(parser).next(response -> {
			input = response.b;
			final line = response.a.force().toString();
			return if (hasCode(line, expectedStatus)) line else new Error(line);
		});
	
	function writeLine(line: String): Promise<Noise>
		return ((line+"\r\n"): IdealSource).pipeTo(output)
			.next(res -> switch res {
				case AllWritten: Noise;
				case e: new Error('Could not write to stream: $e');
			});

	function handshake(): Promise<Array<String>>
		return readLine(220)
			.next(start -> 
				writeLine(if (start.indexOf('ESMTP') == -1) 'HELO' else 'EHLO')
			).next(_ -> {
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

	static function hasOption(options: Array<String>, search: String) {
		for (option in options)
			if (option.toLowerCase().indexOf(search) > -1)
				return true;
		return false;
	}

	public static function connect(options: ConnectionOptions): Promise<SmtpMailer> {
		function toMailer(socket: Socket): SmtpMailer
			return new SmtpMailer(socket.input, socket.output, socket.close);
		function connect(socket: Socket): Promise<SmtpMailer> 
			return socket
				.connect(new Host(options.host), options.port)
				.next(_ -> toMailer(socket));
		function upgradeTls(socket: Socket, mailer: SmtpMailer): Promise<SmtpMailer>
			return mailer.readLine(220)
				.next(_ -> SslSocket.upgrade(socket))
				.next(socket -> toMailer(socket))
				.next(upgraded -> 
					upgraded.writeLine('EHLO ' + Host.localhost())
						.next(_ -> upgraded)
				);
		return switch options {
			case {secure: true} | {secure: null, port: 465}:
				connect(new SslSocket());
			default:
				final socket = new Socket();
				connect(socket)
					.next(mailer ->
						mailer.handshake().next(options ->
							if (hasOption(options, 'starttls'))
								upgradeTls(socket, mailer);
							else mailer
						)
					);
		}
	}
}

	/*var start: String = '';
			try {
				@await socket.connect(new Host(connection.host), connection.port);
				socket.setTimeout(5);
				source = socket.input;
				start = @await readLine(220);
			} catch (e: Dynamic) {
				throw 'Could not connect to host: '+e;
			}
			var command = (connection.auth == null && start.indexOf('ESMTP') == -1 ? 'HELO' : 'EHLO');
			@await writeLine(command + ' ' + Host.localhost());
			options = @await getOptions();
			switch connection.secure {
				case StartTls | Auto if (hasOption(['starttls'])):
					@await startTls();
				default:
			}

			if (connection.auth != null)
				if (!hasOption(['login', 'auth']))
					throw 'Server does not support auth login';
				else
					@await auth();

			connected = true;
			return Noise;
		}

		var socket: Socket;

		public function new(connection)
			this.connection = connection;

		public function send(email: Email) {
			var trigger = Future.trigger();
			queue.push(new Pair(email, trigger));
			processQueue();
			return trigger.asFuture();
		}

		@async function sendMessage(email: Email) {
			var encoded: String = MultipartEncoder.encode(email);
			try {
				@await connect();
				@await writeLine('MAIL from: ${email.from.address}');
				@await readLine(250);
				for (user in email.to) {
					@await writeLine('RCPT to: ${user.address}');
					@await readLine(250);
				}
				@await writeLine('DATA');
				@await readLine(354);
				switch @await (encoded: IdealSource).pipeTo(socket.output) {
					case AllWritten:
					default: throw 'Could not write to stream';
				}
				@await writeLine('');
				@await writeLine('.');
				@await readLine(250);
				return Noise;
			} catch (e: Dynamic) {
				if (connected) {
					socket.close();
					connected = false;
				}
				throw e;
			}
		}

		@async function connect() {
			if (connected)
				return Noise;

			socket = switch connection.secure {
				case No | StartTls: new Socket();
				case Ssl: new asys.ssl.Socket();
				case Auto:
					connection.port == 465
					? new asys.ssl.Socket()
					: new Socket();
			}

			var start: String = '';
			try {
				@await socket.connect(new Host(connection.host), connection.port);
				socket.setTimeout(5);
				source = socket.input;
				start = @await readLine(220);
			} catch (e: Dynamic) {
				throw 'Could not connect to host: '+e;
			}
			var command = (connection.auth == null && start.indexOf('ESMTP') == -1 ? 'HELO' : 'EHLO');
			@await writeLine(command + ' ' + Host.localhost());
			options = @await getOptions();
			switch connection.secure {
				case StartTls | Auto if (hasOption(['starttls'])):
					@await startTls();
				default:
			}

			if (connection.auth != null)
				if (!hasOption(['login', 'auth']))
					throw 'Server does not support auth login';
				else
					@await auth();

			connected = true;
			return Noise;
		}

		@async function startTls() {
			@await writeLine('STARTTLS');
			@await readLine(220);
			socket = asys.ssl.Socket.upgrade(socket);
			@await writeLine('EHLO '+Host.localhost());
			options = @await getOptions();
			return Noise;
		}

		@async function auth() {
			@await writeLine('AUTH LOGIN');
			@await readLine(334);
			@await writeLine(Base64.encode(Bytes.ofString(connection.auth.username)));
			@await readLine(334);
			@await writeLine(Base64.encode(Bytes.ofString(connection.auth.password)));
			@await readLine(235);
			return Noise;
		}

		function hasOption(tokens: Array<String>): Bool {
			for (option in options) {
				var matches = true;
				for (token in tokens) {
					if (option.toLowerCase().indexOf(token.toLowerCase()) == -1)
						matches = false;
				}
				if (matches)
					return true;
			}
			return false;
		}

		@async function getOptions() {
			var options = [];
			while (true) {
				var line: String = @await readLine(250);
				options.push(line);
				if (line.substr(3, 1) == '-')
					continue;
				break;
			}
			return options;
		}

		@async function writeLine(line: String) {
			switch @await ((line+"\r\n"): IdealSource).pipeTo(socket.output) {
				case AllWritten:
					return Noise;
				default:
					throw 'Could not write to stream';
			}
		}

		function hasCode(line: String, code: Int) {
			var str = Std.string(code);
			return line.substr(0, str.length) == str;
		}

		@async function readLine(expectedStatus: Int) {
			if (source == null) throw 'Could not read from stream';
			var response = @await source.parse(parser);
			source = response.b;
			var line = response.a.force().toString();
			if (!hasCode(line, expectedStatus))
				throw line;
			return line;
	}*/