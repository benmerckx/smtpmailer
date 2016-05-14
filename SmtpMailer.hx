package;

import asys.net.Socket;
import asys.net.Host;
import haxe.io.Bytes;
import haxe.io.Error;
import tink.io.Sink;
import tink.io.IdealSource;
import tink.io.Source;
import tink.io.StreamParser;
import haxe.io.BytesOutput;
import tink.io.Pipe;
import haxe.crypto.Base64;

using tink.CoreApi;

typedef SmtpConnection = {
	host: String,
	port: Int,
	?secure: Secure,
	?auth: {
		username: String,
		password: String
	}
}

typedef Email = {
	from: String,
	to: Array<String>,
	subject: String,
	body: String
}

enum Secure {
	Auto;
	No;
	Ssl;
	StartTls;
}

class UntilLine extends ByteWiseParser<String> {
  
	var buf: StringBuf = new StringBuf();
	
	override function read(c: Int): ParseStep<String> {
		return switch c {
			case 10:
				var ret = buf.toString();
				if (ret.charCodeAt(ret.length-1) == 13) 
					ret = ret.substr(0, -1);
				if (ret == '')
					Progressed;
				else {
					buf = new StringBuf();
					Done(ret);
				}
			default:
				buf.addChar(c);
				Progressed;
		}
	}
}


@:build(await.Await.build())
class SmtpMailer {
	
	var socket: Socket;
	var source: Source;
	var connection: SmtpConnection;
	var connected = false;
	var options: Array<String>;

	public function new(connection: SmtpConnection) {
		if (connection.secure == null)
			connection.secure = Secure.Auto;
		this.connection = connection;
	}
	
	function hasCode(line: String, code: Int) {
		var str = Std.string(code);
		return line.substr(0, str.length) == str;
	}
	
	@:async function connect() {
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
		socket.connect(new Host(connection.host), connection.port);
		source = socket.input;
		
		var line: String = @:await readLine();
		var command = (line.indexOf('ESMTP') == -1 ? 'HELO ':'EHLO ');
		@:await writeLine(command+Host.localhost());
		options = @:await getOptions();
		switch connection.secure {
			case StartTls | Auto if (hasOption(['starttls'])):
				@:await startTls();
				if (connection.auth == null)
					return Noise;
				else if (!hasOption(['login', 'auth']))
					throw 'Server does not support auth login';
				else
					return @:await auth();
			default: null;
		}
		return Noise;
	}
	
	@:async function auth() {
		@:await writeLine('AUTH LOGIN');
		if (hasCode(@:await readLine(), 334))
			return @:await login();
		throw 'Server did not respond to starttls command';
	}
	
	@:async function login() {
		@:await writeLine(Base64.encode(Bytes.ofString(connection.auth.username)));
		if (!hasCode(@:await readLine(), 334))
			throw 'Could not authenticate';
		@:await writeLine(Base64.encode(Bytes.ofString(connection.auth.password)));
		if (!hasCode(@:await readLine(), 235))
			throw 'Wrong credentials';
		else
			return Noise;
	}
	
	@:async function startTls() {
		@:await writeLine('STARTTLS');
		if (hasCode(@:await readLine(), 220)) {
			socket = asys.ssl.Socket.upgrade(socket);
			@:await writeLine('EHLO '+Host.localhost());
			options = @:await getOptions();
		}
		return Noise;
	}
	
	@:async public function send(email: Email) {
		try {
			@:await connect();
			@:await writeLine('MAIL from: '+email.from);
			@:await readLine();
			// check 250
			@:await writeLine('RCPT to: '+email.to.join(','));
			@:await readLine();
			// check 250
			@:await writeLine('DATA');
			var line = @:await readLine();
			if (!hasCode(line, 354))
				throw 'Could not send data';
			@:await writeLine('From: '+email.from);
			@:await writeLine('To: '+email.to.join(','));
			@:await writeLine('Subject: '+email.subject);
			@:await writeLine('');
			@:await writeLine(email.body);
			@:await writeLine('');
			@:await writeLine('.');
			if (!hasCode(@:await readLine(), 250))
				throw 'Sending data failed';
			return Noise;
		} catch (e: Dynamic) {
			socket.close();
			throw e;
		}
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
	
	function getOptions(): Future<Array<String>> {
		var trigger = Future.trigger();
		var options = [];
		function addOption(res: Outcome<String, Noise>) switch res {
			case Success(option):
				options.push(option);
				if (option.substr(3, 1) == '-')
					getOption().handle(addOption);
				else
					trigger.trigger(options);
			default:
				trigger.trigger(options);
		}
		getOption().handle(addOption);
		return trigger.asFuture();
	}
	
	@:async function getOption() {
		var line: String = @:await readLine();
		if (hasCode(line, 250))
			return line;
		else
			throw Noise;
	}
	
	@:async function writeLine(line: String) {
		trace('write: '+line);
		source = socket.input;
		switch @:await ((line+"\r\n"): IdealSource).pipeTo(socket.output) {
			case PipeResult.AllWritten: 
				return Noise;
			default: 
				throw 'Could not write to stream';
		}
	}
	
	@:async function readLine() {
		var response = @:await source.parse(new UntilLine());
		source = response.rest;
		trace('read: '+ response.data);
		return response.data;
	}

}
