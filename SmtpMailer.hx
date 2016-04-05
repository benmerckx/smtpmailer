package;

import asys.net.Socket;
import asys.net.Host;
import haxe.Timer;
import tink.io.Sink;
import tink.io.IdealSource;
import tink.io.Source;
import tink.io.StreamParser;
import haxe.io.BytesOutput;
import tink.io.Pipe;

using tink.CoreApi;

typedef SmtpConnection = {
	host: String,
	port: Int,
	secure: Bool,
	?auth: {
		username: String,
		password: String
	}
}

typedef Email = {
	from: String,
	to: Array<String>,
	body: String
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

class SmtpMailer {
	
	var socket: Socket;
	var source: Source;
	var connection: SmtpConnection;
	var connected = false;
	var options: Array<String>;

	public function new(connection: SmtpConnection) {
		this.connection = connection;
	}
	
	function connect(): Surprise<Noise, Error> {
		if (connected)
			return Future.sync(Success(Noise));
		if (connection.secure)
			socket = new asys.ssl.Socket();
		else
			socket = new Socket();
		socket.connect(new Host(connection.host), connection.port);
		source = socket.input;
		
		return
		readLine()
		>> function(line: String) {
			if (line.indexOf('ESMTP') == -1)
				return
				writeLine('HELO '+Host.localhost())
				>> function(x) return switch x {
					case PipeResult.AllWritten: Success(Future.sync([]));
					default: Failure(new Error('Could not read from stream'));
				};
				
			return 
			writeLine('EHLO '+Host.localhost())
			>> function(x) return switch x {
				case PipeResult.AllWritten: 
					Success(getOptions());
				default: Failure(new Error('Could not read from stream'));
			}
		}
		>> function(res) return switch res {
			case Success(options):
				this.options = options;
				connected = true;
				Success(Noise);
			case Failure(e): Failure(e);
		};
	}
	
	public function send(email: Email) {
		connect()
		>> function(_) {
			trace('connected');
			return Success('ok');
		};
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
	
	function getOption(): Surprise<String, Noise>
		return readLine()
		>> function(line: String)
			return StringTools.startsWith(line, '250')
				? Success(line)
				: Failure(Noise);
	
	function writeLine(line: String) {
		source = socket.input;
		return ((line+"\r\n"): IdealSource).pipeTo(socket.output);
	}
	
	function readLine(): Future<String>
		return source.parse(new UntilLine())
		>> function (res) return switch res {
			case Success(response):
				source = response.rest;
				response.data;
			default: '';
		}
	}
}
