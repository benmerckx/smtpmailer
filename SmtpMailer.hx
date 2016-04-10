package;

import asys.net.Socket;
import asys.net.Host;
import haxe.io.Error;
import haxe.Timer;
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
	
	function connect(): Surprise<Noise, Error> {
		if (connected)
			return Future.sync(Success(Noise));
			
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
		
		return readLine()
		>> function(line: String) {
			if (line.indexOf('ESMTP') == -1)
				return writeLine('HELO '+Host.localhost())
				>> function(res) return switch res {
					case PipeResult.AllWritten: [];
					default: throw 'Could not write to stream';
				};
				
			return writeLine('EHLO '+Host.localhost())
			>> function(res) return switch res {
				case PipeResult.AllWritten: getOptions();
				default: throw 'Could not write to stream';
			};
		}
		>> function (options: Array<String>) {
			this.options = options;
			return switch connection.secure {
				case StartTls | Auto if (hasOption(['starttls'])):
					startTls();
				default:
					Future.sync(Success(Noise));
			}
		}
		>> function (res): Surprise<Noise, Error> return switch res {
			case Success(_):
				if (connection.auth == null)
					Future.sync(Success(Noise));
				else if (!hasOption(['login', 'auth']))
					Future.sync(Failure(new Error('Server does not support auth login')));
				else
					auth();
			case Failure(e): 
				Future.sync(Failure(e));
		};
	}
	
	function auth(): Surprise<Noise, Error> {
		return writeLine('AUTH LOGIN')
		>> function(res) return switch res {
			case PipeResult.AllWritten:
				return readLine()
				>> function (line: String) {
					return
					if (line.substr(0, 3) == '334')
						Future.sync(Failure(new Error('Do login')));
					else
						Future.sync(Failure(new Error('Server did not respond to starttls command')));
				};
			default:
				Future.sync(Failure(new Error('Could not write auth to stream')));
		};
	}
	
	/*function login(): Surprise<Noise, Error> {
		return writeLine(Base64.encode(connection.auth.)
	}*/
	
	function startTls() {
		return writeLine('STARTTLS')
		>> function(res) return switch res {
			case PipeResult.AllWritten:
				return 
				readLine()
				>> function (line: String) {
					if (line.substr(0, 3) == '220') {
						socket = asys.ssl.Socket.upgrade(socket);
						return Success(Noise);
					}
					return Failure(new Error('Server did not respond to starttls command'));
				};
			default: 
				Future.sync(Failure(new Error('Could not initiate starttls')));
		}
		>> function(res) return switch res {
			case Success(_):
				return writeLine('EHLO '+Host.localhost())
				>> function(res) return switch res {
					case PipeResult.AllWritten: 
						getOptions();
					default: throw 'Could not write to stream';
				}
				>> function (options: Array<String>) {
					this.options = options;
					return Success(Noise);
				}
			case Failure(e): 
				Future.sync(Failure(e));
		}
	}
	
	public function send(email: Email): Surprise<Noise, Error> {
		return connect()
		>> function(res) return switch res {
			case Success(_):
				Success(Noise);
			case Failure(e):
				Failure(e);
		};
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
	
	function getOption(): Surprise<String, Noise>
		return readLine()
		>> function(line: String)
			return StringTools.startsWith(line, '250')
				? Success(line)
				: Failure(Noise);
	
	function writeLine(line: String) {
		trace('write: '+line);
		source = socket.input;
		return ((line+"\r\n"): IdealSource).pipeTo(socket.output);
	}
	
	function readLine(): Future<String>
		return source.parse(new UntilLine())
		>> function (res) return switch res {
			case Success(response):
				trace('read: '+response.data);
				source = response.rest;
				response.data;
			default: '';
		}
	}
}
