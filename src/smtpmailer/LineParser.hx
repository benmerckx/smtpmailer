package smtpmailer;

import tink.io.StreamParser;

class LineParser extends Splitter {
	public function new() {
		super('\r\n');
	}
}