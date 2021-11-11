// hi :)
function praux_error (message, ms) {
    // make sure ms is set to a true value.
    if (!ms) {
        ms = 3000;
    }
    
    if (!message) {
        message = "An unknown error occurred, please contact <a href='mailto:sysop@praux.com'>sysop@praux.com</a>!";
        ms = 10000;
    }
    
    timeout = setTimeout(function() {
        if($('.jbar').length){
			clearTimeout(timeout);
			$('.jbar').fadeOut('fast',function(){
				$(this).remove();
			});
		}
    }, ms);
    
	var _message_span = $(document.createElement('span')).addClass('jbar-content').html(message);
	_message_span.css({"color" : '#cf4c43'});
	var _wrap_bar;

    _wrap_bar = $(document.createElement('div')).addClass('jbar jbar-top');

	_wrap_bar.css({"background-color" 	: '#FFFFFF'});			
	_wrap_bar.css({"cursor"	: "pointer"});
	_wrap_bar.append(_message_span).insertBefore('.site-header').fadeIn('fast');
}