/*
 * Copyright (c) 2006, Motion-Twin
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   - Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   - Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY MOTION-TWIN "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE HAXE PROJECT CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */
package mtwin.mail;

#if haxe3
import haxe.crypto.BaseCode;
import haxe.Utf8;
#else
import haxe.BaseCode;
import neko.Utf8;
#end

typedef Address = {
	name: String,
	address: String
}

class Tools {

	static var BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	static var HEXA = "0123456789ABCDEF";


	static var REG_HEADER_DECODE = ~/^(.*?)=\?([^\?]+)\?(Q|B)\?([^?]*)\?=\s*(.*?)$/i;
	static var REG_QP_LB = ~/=\\r?\\n/;
	static var REG_QP = ~/=([A-Fa-f0-9]{1,2})/;
	static var REG_SPACES_EQUAL = ~/[\s=]+/g;

	public static function chunkSplit( str:String, length:Int, sep:String ){
		var ret = "";
		while( str.length > length ){
			ret += str.substr(0,length) + sep;
			str = str.substr(length,str.length - length);
		}
		return ret + str;
	}

	public static function splitLines( str : String ) : Array<String> {
		var ret = str.split("\n");
		for( i in 0...ret.length ){
			var l = ret[i];
			if( l.substr(-1,1) == "\r" ){
				ret[i] = l.substr(0,-1);
			}
		}
		return ret;
	}

	public static function encodeBase64( content : String ){
		return StringTools.rtrim(chunkSplit(content, 76, "\r\n"));
	}

	#if neko
	static var regexp_match = neko.Lib.load("regexp","regexp_match",4);
	static var regexp_matched_pos : Dynamic -> Int -> { pos : Int, len : Int } = neko.Lib.load("regexp","regexp_matched_pos",2);
	#end

	public static function decodeBase64( content : String ){
		#if neko
		var r = untyped ~/[\s=]+/.r;
		var b = new StringBuf();
		var pos = 0;
		var len = content.length;
		var first = true;
		do {
			if( !regexp_match(r,untyped content.__s,pos,len) )
				break;
			var p = regexp_matched_pos(r,0);
			if( p.len == 0 && !first ) {
				if( p.pos == content.length )
					break;
				p.pos += 1;
			}
			b.addSub(content,pos,p.pos-pos);
			var tot = p.pos + p.len - pos;
			pos += tot;
			len -= tot;
			first = false;
		} while( true );
		b.addSub(content,pos,len);
		content = b.toString();
		#else
		content = REG_SPACES_EQUAL.replace(content,"");
		#end
		return try BaseCode.decode( content, BASE64 ) catch( e : Dynamic ) content;
	}

	public static function encodeQuotedPrintable( content : String ) : String{
		#if php
		return php.Syntax.code("quoted_printable_encode({0})", content);
		#else
		var rs = new List();
		var lines = splitLines( content );

		for( ln in lines ){
			#if nodejs
			var buff = js.node.Buffer.from(ln);
			var len = buff.length;
			#else
			var len = ln.length;
			#end
			var line = "";
			for( i in 0...len ){
				#if nodejs
				var c = String.fromCharCode(buff[i]);
				#else
				var c = ln.charAt(i);
				#end
				var o = c.charCodeAt(0);
				if( o == 9 ){
				}else if( o < 16 ){
					c = "=0" + StringTools.hex(o);
				}else if( o == 61 || o < 32 || o > 126 ){
					c = "=" + StringTools.hex(o);
				}

				// space at the end of line
				if( i == len - 1 ){
					if( o == 32 ){
						c = "=20";
					}else if( o == 9 ){
						c = "=09";
					}
				}

				// soft line breaks
				var ll = line.length;
				var cl = c.length;
				if( ll + cl >= 76 && (i != len -1 || ll + cl != 76) ){
					rs.add(line + "=");
					line = "";
				}
				line += c;
			}
			rs.add(line);
		}

		return rs.join("\r\n");
		#end
	}

	static var REG_HEXA = ~/^[0-9A-F]{2}$/;
	public static function decodeQuotedPrintable( str : String ){
		#if php
		return php.Syntax.code("quoted_printable_decode({0})", str);
		#else
		str = ~/=\r?\n/g.replace(str,"");
		var a = str.split("=");
		var first = true;
		var ret = new StringBuf();
		for( t in a ){
			if( first ){
				first = false;
				ret.add(t);
			}else{
				var h = t.substr(0,2).toUpperCase();
				if( REG_HEXA.match(h) ){
					ret.add(BaseCode.decode(h,HEXA));
					ret.addSub(t,2,t.length - 2);
				}else{
					ret.add("=");
					ret.add(t);
				}

			}
		}
		return ret.toString();
		#end
	}

	public static function headerQpEncode( ostr : String, initSize : Int, charset : String, ?cleanQuote : Bool ){
		var str = ~/\r?\n\s*/.replace(ostr," ");
		if( cleanQuote ){
			if( str.substr(0,1) == "\"" )
				str = str.substr(1,str.length-1);
			if( str.substr(str.length-1,1) == "\"" )
				str = str.substr(0,str.length-1);
		}

		var csl = charset.length;
		var len = str.length;
		var quotedStr : List<String> = new List();
		var line = new StringBuf();
		var llen = 0;
		var useQuoted = false;
		for( i in 0...len ){
			var c = str.charAt(i);
			var o = c.charCodeAt(0);

			if( o == 9 ){
			}else if( o < 16 ){
				useQuoted = true;
				c = "=0" + BaseCode.encode(c,HEXA);
			}else if( o == 61 || o == 58 || o == 63 || o == 95 || o == 34 ){
				c = "=" + BaseCode.encode(c,HEXA);
			}else if( o < 32 || o > 126 ){
				useQuoted = true;
				c = "=" + BaseCode.encode(c,HEXA);
			}else if( o == 32 ){
				c = "_";
			}

			// max line length = 76 - 17 ( =?iso-8859-1?Q?...?= ) => 59 - initSize
			var max : Int;
			if( quotedStr.length == 0 ){
				max = 69 - csl - initSize;
			}else{
				max = 69 - csl;
			}
			var clen = c.length;
			if( llen + clen >= max ){
				quotedStr.add(line.toString());
				line = new StringBuf();
				llen = 0;
			}
			line.add(c);
			llen += clen;
		}
		quotedStr.add(line.toString());

		if( !useQuoted ){
			return wordWrap(ostr,75,"\r\n",initSize,true);
		}else{
			return "=?"+charset+"?Q?"+quotedStr.join("?=\r\n =?"+charset+"?Q?")+"?=";
		}
	}

	public static function headerAddressEncode( ostr : String, initSize : Int, charset : String ){
		var list = parseAddress(ostr);
		var lret = new List();
		for( a in list ){
			var ret = new StringBuf();
			var addr = a.address;
			if( a.name != null ){
				var name = a.name;
				if( ~/[\s,"']/.match( name ) )
					name = "\""+name.split("\\").join("\\\\").split("\"").join("\\\"")+"\"";
				var t = headerQpEncode(name,initSize,charset,true);
				ret.add( t );
				var p = t.lastIndexOf("\n");
				if( p == -1 )
					initSize += t.length;
				else
					initSize = t.length - p;
				addr = " <"+a.address+">";
			}

			if( initSize + addr.length > 75 ){
				ret.add("\r\n ");
				initSize = 1;
			}
			ret.add( addr );
			initSize += addr.length;
			lret.add( ret.toString() );
		}
		return lret.join(", ");
	}

	public static function headerComplexEncode( ostr : String, initSize : Int, charset : String ){
		var e = parseComplexHeader(ostr);
		var ret = new StringBuf();

		var b = headerQpEncode(e.value,initSize,charset);
		ret.add(b);

		for( k in e.params.keys() ){
			ret.add(";");
			initSize += 1;
			var p = b.lastIndexOf("\n");
			if( p == -1 )
				initSize += b.length;
			else
				initSize = b.length - p;

			if( initSize + k.length + 3 > 75 ){
				ret.add("\r\n ");
				initSize = 1;
			}else{
				ret.add(" ");
				initSize++;
			}
			ret.add(k);
			ret.add("=\"");
			initSize += k.length + 2;
			b = headerQpEncode(e.params.get(k),initSize,charset);
			ret.add(b);
			ret.add("\"");
		}

		return ret.toString();
	}

	public static function headerDecode( str : String, charsetOut : String ){
		str = ~/\r?\n\s?/.replace(str," ");
		while( REG_HEADER_DECODE.match(str) ){
			var charset = StringTools.trim(REG_HEADER_DECODE.matched(2).toLowerCase());
			var encoding = StringTools.trim(REG_HEADER_DECODE.matched(3).toLowerCase());
			var encoded = StringTools.trim(REG_HEADER_DECODE.matched(4));

			var start = REG_HEADER_DECODE.matched(1);
			var end = REG_HEADER_DECODE.matched(5);

			if( encoding == "q" ){
				encoded = decodeQuotedPrintable(StringTools.replace(encoded,"_"," "));
			}else if( encoding == "b" ){
				encoded = decodeBase64(encoded);
			}else{
				throw "Unknow transfer-encoding: "+encoding;
			}

			charsetOut = charsetOut.toLowerCase();
			if( charsetOut != "utf-8" && charset == "utf-8" ){
				encoded =  try Utf8.decode( encoded ) catch( e : Dynamic ) encoded;
			}else if( charset != "utf-8" && charsetOut == "utf-8" ){
				encoded =  try Utf8.encode( encoded ) catch( e : Dynamic ) encoded;
			}

			str = start + encoded + end;
		}

		return str;
	}

	public static function removeCRLF( str ){
		return StringTools.replace(StringTools.replace(str,"\n",""),"\r","");
	}

	public static function formatHeaderTitle( str : String ) : String {
		str = StringTools.trim( str );
		if( str.toLowerCase() == "mime-version" ) return "MIME-Version";

		var arr = str.split("-");
		for( i in 0...arr.length ){
			var t = arr[i];
			arr[i] = t.substr(0,1).toUpperCase()+t.substr(1,t.length-1).toLowerCase();
		}
		return arr.join("-");
	}

	public static function randomEight(){
		var s = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";

		var ret = "";
		for( i in 0...8 ){
			ret += s.charAt(Std.random(s.length));
		}
		return ret;
	}

	public static function pregQuote( str : String ){
		str = StringTools.replace(str,"\\","\\\\");
		str = StringTools.replace(str,".","\\.");
		str = StringTools.replace(str,"+","\\+");
		str = StringTools.replace(str,"*","\\*");
		str = StringTools.replace(str,"?","\\?");
		str = StringTools.replace(str,"^","\\^");
		str = StringTools.replace(str,")","\\)");
		str = StringTools.replace(str,"(","\\(");
		str = StringTools.replace(str,"[","\\[");
		str = StringTools.replace(str,"]","\\]");
		str = StringTools.replace(str,"{","\\{");
		str = StringTools.replace(str,"}","\\}");
		str = StringTools.replace(str,"=","\\=");
		str = StringTools.replace(str,"!","\\!");
		str = StringTools.replace(str,"<","\\<");
		str = StringTools.replace(str,">","\\>");
		str = StringTools.replace(str,"|","\\|");
		str = StringTools.replace(str,":","\\:");
		str = StringTools.replace(str,"$","\\$");
		str = StringTools.replace(str,"/","\\/");

		return str;
	}

	public static function formatHeader( name : String, content : String, charset : String ){
		var lname = name.toLowerCase();
		if( lname == "to" || lname == "from" || lname == "cc" || lname == "bcc" ){
			return name+": "+headerAddressEncode(content,name.length+2,charset)+"\r\n";
		}else if( lname.substr(0,8) == "content-" ){
			return name+": "+headerComplexEncode(content,name.length+2,charset)+"\r\n";
		}else{
			return name+": "+headerQpEncode(content,name.length+2,charset)+"\r\n";
		}

	}

	static var REG_MHEADER = ~/^([^;]+)(.*?)$/;
	static var REG_PARAM1 = ~/^;\s*([a-zA-Z]+)="(([^"]|\\")+)"/;
	static var REG_PARAM2 = ~/^;\s*([a-zA-Z]+)=([^;]+)/;
	public static function parseComplexHeader( h : String ){
		if( h == null ) return null;

		var ret = {value: null, params: #if haxe3 new Map() #else new Hash() #end};
		if( REG_MHEADER.match(h) ){
			ret.value = StringTools.trim( REG_MHEADER.matched(1) );

			var params = REG_MHEADER.matched(2);
			while( params.length > 0 ){
				params = StringTools.ltrim( params );

				if( REG_PARAM1.match( params ) ){
					var k = StringTools.trim(REG_PARAM1.matched(1)).toLowerCase();
					var v = REG_PARAM1.matched(2);
					ret.params.set( k, v );
					params = REG_PARAM1.matchedRight();
				}else if( REG_PARAM2.match( params ) ){
					var k = StringTools.trim(REG_PARAM2.matched(1)).toLowerCase();
					var v = StringTools.trim(REG_PARAM2.matched(2));
					ret.params.set( k, v );
					params = REG_PARAM2.matchedRight();
				}else{
					break;
				}
			}
		}else{
			ret.value = h;
		}
		return ret;

	}

	public static function wordWrap( str : String, ?length : Int, ?sep : String, ?initCur : Int, ?keepSpace : Bool ){
		if( length == null ) length = 75;
		if( sep == null ) sep = "\n";
		if( initCur == null ) initCur = 0;
		if( keepSpace == null ) keepSpace = false;


		var reg = ~/(.*?)(\s+)/;
		var a = new Array();
		while( reg.match(str) ){
			var c = reg.matched(1);
			var s = reg.matched(2);
			var l = c.length+s.length;
			a.push( c );
			a.push( s );
			str = str.substr(l,str.length-l);
		}
		a.push( str );

		var sb = new StringBuf();
		var cur = initCur;
		var n = a[0];
		for( i in 0...a.length ){
			var e = n;
			n = a[i+1];

			var cut = false;
			if( i%2 == 1 && cur + e.length + n.length > length ){
				cut = true;
				if( keepSpace ){
					for( is in 0...e.length-1 ){
						if( cur >= length ){
							sb.add( sep );
							cur = 0;
						}
						sb.addSub(e,is,1);
						cur++;
					}
					if( cur + 1 + n.length > length ){
						sb.add(sep);
						cur = 0;
					}
					sb.add(e.substr(-1,1));
					cur++;
				}else{
					sb.add( sep );
					cur = 0;
				}
			}
			if( i % 2 != 1 || !cut ){
				sb.add( e );
				cur += e.length;
			}
		}

		return sb.toString();
	}

	// TODO routes & groups ?
	static var REG_ADDRESS = ~/^(([^()<>@,;:\\"\[\]\s]+|"(\\"|[^"])*")@[A-Z0-9][A-Z0-9-.]*)/i;
	static var REG_ROUTE_ADDR = ~/^<(([^()<>@,;:\\"\[\]\s]+|"(\\"|[^"])*")@[A-Z0-9][A-Z0-9-.]*)>/i;
	static var REG_ATOM = ~/^([^()<>@,;:"\[\]\s]+)/i;
	static var REG_QSTRING = ~/^"((\\"|[^"])*)"/;
	static var REG_COMMENT = ~/^\(((\\\)|[^)])*)\)/;
	static var REG_SEPARATOR = ~/,\s*/;
	public static function parseAddress( str : String, ?vrfy : Bool ) : Array<Address> {
		if( vrfy == null )
			vrfy = true;
		var a = new Array();
		var name = null;
		var address = null;

		str = StringTools.trim(str);
		var s = str;

		while( s.length > 0 ){
			s = StringTools.ltrim(s);
			if( REG_QSTRING.match(s) ){
				var t = REG_QSTRING.matched(1);
				t = ~/\\(.)/g.replace(t,"$1");
				if( name != null ) name += " ";
				else name = "";
				name += t;
				s = REG_QSTRING.matchedRight();
			}else if( REG_ADDRESS.match(s) ){
				if( address != null && vrfy ) throw Exception.ParseError(str+", near: "+s.substr(0,15));
				address = REG_ADDRESS.matched(1);
				s = REG_ADDRESS.matchedRight();
			}else if( REG_ROUTE_ADDR.match(s) ){
				if( address != null )
					name = (name!=null)?name+" "+address : address;
				address = REG_ROUTE_ADDR.matched(1);
				s = REG_ROUTE_ADDR.matchedRight();
			}else if( REG_ATOM.match(s) ){
				if( name != null ) name += " ";
				else name = "";
				name += REG_ATOM.matched(1);
				s = REG_ATOM.matchedRight();
			}else if( REG_COMMENT.match(s) ){
				if( name != null ) name += " ";
				else name = "";
				name += REG_COMMENT.matched(1);
				s = REG_COMMENT.matchedRight();
			}else if( REG_SEPARATOR.match(s) ){
				if( address != null ){
					a.push({name: if( name != null && name.length > 0 ) name else null, address: address});
					address = null;
					name = null;
				}
				s = REG_SEPARATOR.matchedRight();
			}else if( vrfy ){
				throw Exception.ParseError(str+", near: "+s.substr(0,15));
			}else{
				break;
			}
		}
		if( address != null ){
			a.push({name: if( name != null && name.length > 0 ) name else null, address: address});
		}
		if( a.length == 0 ){
			if( vrfy )
				throw Exception.ParseError(str+", no address found");
			else
				a.push({name: null,address: null});
		}
		return a;
	}

	public static function formatAddress( a : Array<Address> ){
		var r = new List();
		for( c in a ){
			if( c.name == null || c.name == "" ) r.add('<'+c.address+'>');
			else{
				var quoted = c.name.split("\\").join("\\\\").split("\"").join("\\\"");
				r.add("\""+quoted+"\" <"+c.address+">");
			}
		}
		return r.join(",");
	}

}
