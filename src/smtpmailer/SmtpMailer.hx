package smtpmailer;

import asys.net.Socket;
import asys.net.Host;
import haxe.io.Bytes;
import haxe.io.Error;
import haxe.io.BytesOutput;
import haxe.crypto.Base64;
import tink.io.Sink;
import tink.io.IdealSource;
import tink.io.Source;
import tink.io.Pipe;

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

enum Secure {
	Auto;
	No;
	Ssl;
	StartTls;
}

class SmtpMailer implements await.Await {
	
	var socket: Socket;
	var source: Source;
	var connection: SmtpConnection;
	var connected = false;
	var options: Array<String>;
	var parser = new LineParser();
	var queue: Array<Pair<Email, FutureTrigger<Outcome<Noise, Dynamic>>>> = [];
	var processing = false;

	public function new(connection: SmtpConnection) {
		if (connection.secure == null)
			connection.secure = Secure.Auto;
		this.connection = connection;
	}
	
	public function send(email: Email) {
		var trigger = Future.trigger();
		queue.push(new Pair(email, trigger));
		processQueue();
		return trigger.asFuture();
	}
	
	@await function processQueue() {
		if (!processing) {
			processing = true;
			while (queue.length > 0) {
				var pair = queue.shift(),
					email = pair.a,
					trigger = pair.b;
				
				trigger.trigger(
					try Success(@await sendMessage(email))
					catch(e: Dynamic) Failure(e)
				);
			}
			processing = false;
			#if nodejs
			if (connected) {
				connected = false;
				socket.close();
			}
			#end
		}
	}
	
	@async function sendMessage(email: Email) {
		var encoded: String = MultipartEncoder.encode(email);
		try {
			@await connect();
			@await writeLine('MAIL from: '+email.from);
			@await readLine(250);
			for (user in email.to) {
				@await writeLine('RCPT to: '+user);
				@await readLine(250);
			}
			@await writeLine('DATA');
			@await readLine(354);
			switch @await (encoded: IdealSource).pipeTo(socket.output) {
				case PipeResult.AllWritten:
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
		
		var start: String;
		try {
			@await socket.connect(new Host(connection.host), connection.port);
			socket.setTimeout(5);
			source = socket.input;
			start = @await readLine(220);
		} catch (e: Dynamic) {
			throw 'Could not connect to host: '+e;
		}
		var command = (start.indexOf('ESMTP') == -1 ? 'HELO ':'EHLO ');
		@await writeLine(command+Host.localhost());
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
		source = socket.input;
		switch @await ((line+"\r\n"): IdealSource).pipeTo(socket.output) {
			case PipeResult.AllWritten: 
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
		source = response.rest;
		var line = response.data;
		if (!hasCode(line, expectedStatus))
			throw line;
		return line;
	}
}