package smtpmailer;

class AddressTools {
    public static function sanitizeAddress( address: String )
        return address.indexOf('<') > -1
            ? address
            : '<$address>';
}
