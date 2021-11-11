/*
   Praux.com
   (c) 2010 Michael Gregorowicz - All Rights Reserved
*/
var mode = 'view';
var modifier_engaged;
var lce = false;
var lcs = false;
var tried;
var pc_click_count = 0;
var expanded = false;
var debug = false;
var growl = true;
var translate_all = false;

$(function() {
    // do this first after the page loads
    tried = login_tried;
    
    // jGrowl defaults
    $.jGrowl.defaults.position = 'bottom-right';
    $.jGrowl.defaults.life = 5000;
    
    // show cursor while ajaxing!
    $('body').ajaxStart(function() {
        $(this).css('cursor', 'wait');
    });
    
    $('body').ajaxStop(function() {
        $(this).css('cursor', '');
    });

    $(".fg-button:not(.ui-state-disabled)").hover(
        function(){ 
            $(this).addClass("ui-state-hover"); 
        },
        function(){ 
            $(this).removeClass("ui-state-hover"); 
        }
    ).mousedown(function(){
            $(this).parents('.fg-buttonset-single:first').find(".fg-button.ui-state-active").removeClass("ui-state-active");
            if( $(this).is('.ui-state-active.fg-button-toggleable, .fg-buttonset-multi .ui-state-active') ){ $(this).removeClass("ui-state-active"); }
            else { $(this).addClass("ui-state-active"); }   
    }).mouseup(function(){
        if(! $(this).is('.fg-button-toggleable, .fg-buttonset-single .fg-button, .fg-buttonset-multi .fg-button') ){
            $(this).removeClass("ui-state-active");
        }
        
        if (active_user) {
            if ($(this).is('#edit_mode')) {
                if (is_mine) {
                    if (mode != 'edit') {
                        init_edit();
                        mode = 'edit';
                    }
                } else {
                    flash_error('Error:', 'Only the owner of this resume can edit it.');
                    $(this).removeClass("ui-state-active");
                }
            } else if ($(this).is('#modify_details')) {
                document.location = '/edit_resume/';
            } else if ($(this).is('#left_click_edit')) {
                if (is_mine) {
                    lce = true;
                    lcs = false;
                    left_click_edit();
                }
            } else if ($(this).is('#left_click_sort')) {
                if (is_mine) {
                    lce = false;
                    lcs = true;
                    left_click_sort();
                }
            } else if ($(this).is('#subscribe')) {
                init_subscribe();
            } else if ($(this).is('#favorites')) {
                init_favorites();
            } else if ($(this).is('#talent_portfolios')) {
                init_talent_portfolios();
            }
        } else {
            tried = $(this).attr('id');
            $(this).removeClass("ui-state-active");
            if ($('#login_box').is(':hidden')) {
                $('.helper_shadow').animate({
                    height: '+=155px'
                }, 250);

                $('.helper_content').animate({
                    height: '+=175px'
                }, 250, function() {
                    $('#login_box').fadeIn(250);
                });
            } else {
                // no -- you really cant do this.. blink something..
                $('#please_log_in').effect('highlight', {}, 1500);
            }
        }
        $(this).blur();
    });

    // fixing a hole where the rain gets in... cplater <3
    $('form.dialog_form').submit(function() {
        $(this).parents('div.ui-dialog').find('div.ui-dialog-buttonpane button:first').click();
        return false;
    });
    
    // return in textareas submits forms in dialogs.
    $('form.dialog_form textarea').keydown(function(e) {
        if (e.keyCode == 13) {
            $(this).parents('form.dialog_form').submit();
        }
    });

    // the suggestion dialog
    $('#suggestion_dialog').dialog({
        bgiframe: true,
        autoOpen: false,
        height: 510,
        width: 625,
        modal: true,
        buttons: {
            'Accept': function() {
                if ($('#suggestion_final_value').val() != undefined) {
                    // hit it like this
                    var submit_data = {};
                    submit_data['suggestion_final_value'] = $('#suggestion_final_value').val();
                    submit_data['suggestion'] = $('#suggestion_select option:selected').attr('suggestion_id');
                
                    prauxn_home('set_suggestion', submit_data, 
                        function(data) {
                            // edit means they differed enough to not give credit. (right now it means they differed at all)
                            if (data['Praux::Url::JSON::SetSuggestion'] != undefined) {
                                $.each(data['Praux::Url::JSON::SetSuggestion'], function(i, n) {
                                    $('#' + n.html_id).text(n.display_value);
                                    $('#' + n.html_id).effect('highlight', {}, 1500);
                                });
                            }
                        
                            // clear our datas
                            $('#suggestion_final_value').val('');
                            
                            var location = document.location.toString();
                            var match = location.match(/(.+?)\/([\.\#]\w+)\/([\w\-]*)\/?$/);
                            if (match) {
                                document.location = match[1] + "/";
                            }
                        }
                    );
                }
                
                $(this).dialog('close');

            },
            'Delete': function() {
                var submit_data = {};
                submit_data['content_item'] = $('#suggestion_select').val();
                prauxn_home('remove_suggestion', {suggestion: $('#suggestion_select option:selected').attr('suggestion_id')},
                    function(data) {
                        $('#suggestion_select option[suggestion_id=' + data.suggestion  + ']').remove();
                        $('#suggestion_select').change();
                    }
                );
            },
            'Cancel': function() {
                $('#suggestion_final_value').val('');
                $(this).dialog('close');
                var location = document.location.toString();
                var match = location.match(/(.+?)\/([\.\#]\w+)\/([\w\-]*)\/?$/);
                if (match) {
                    document.location = match[1] + "/";
                }
            }   
        }
    });

    // the value dialog
    $('#value_dialog').dialog({
        bgiframe: true,
        autoOpen: false,
        height: 390,
        width: 625,
        modal: true,
        buttons: {
            'Save': function() {
                
                if (!$('#itemvalue').val()) {
                    alert("No value specified, if you are trying to delete this content please close this edit dialog, right click the content and select 'delete'");
                    return false;
                }
                
                var id_type = $('#itemid').val().split(/-/);
                
                // hit it like this
                var submit_data = {};
                submit_data[id_type[1]] = $('#itemvalue').val();
                submit_data['content_block'] = id_type[0];
                submit_data['language'] = lang;
                submit_data['html_id'] = $('#itemid').val();
                
                var action = $('#value_form').attr('action');
                
                if (action == "comment") {
                    submit_data['comment'] = $('#itemvalue').val();
                } else if (action == "add_suggestion") {
                    submit_data['suggested_attribute'] = id_type[1];
                    submit_data['suggested_value'] = $('#itemvalue').val();
                }
                
                prauxn_home(action, submit_data, 
                    function(data) {
                        // go through returned values from EditContentItem on this request.
                        // if they're suggestions or comments they'll do nothing. 
                        // this should be converted into a switch statement it looks like.
                        if (data['Praux::Url::JSON::EditContentItem'] != undefined) {
                            $.each(data['Praux::Url::JSON::EditContentItem'], function(i, n) {
                                if (n.rendered_block != null) {
                                    $('#' + n.html_id).replaceWith(n.rendered_block);
                                    init_edit($('#' + n.html_id));
                                } else {
                                    $('#' + n.html_id).text(n.display_value);
                                    $('#' + n.html_id).attr('origvalue', n.display_value);
                                }
                                $('#' + n.html_id).effect('highlight', {}, 1500);
                            });
                        } else if (data['Praux::Url::JSON::AddSuggestion'] != undefined) {                        
                            // may as well do the add content items too!
                            $.each(data['Praux::Url::JSON::AddSuggestion'], function(i, n) {
                                $('#' + n.html_id).effect('highlight', {}, 1500);
                            });
                        } else if (data['Praux::Url::JSON::AddContentItem'] != undefined) {                        
                            // may as well do the add content items too!
                            $.each(data['Praux::Url::JSON::AddContentItem'], function(i, n) {
                                $('#' + n.html_id).effect('highlight', {}, 1500);
                            });
                        } else if (data['Praux::Url::JSON::Comment'] != undefined) {
                            $.each(data['Praux::Url::JSON::Comment'], function(i, n) {
                                $('#' + n.html_id).effect('highlight', {color: 'blue'}, 1500);
                            })
                        } 
                        
                        // clear our datas
                        $('#itemvalue').val('');
                        $('#itemid').val('');
                        $('#value_form').attr('action', '');
                    }
                );
                $(this).dialog('close');
            },  
            'Cancel': function() {
                $('#itemvalue').val('');
                $('#itemid').val('');
                $(this).dialog('close');
            }   
        }
    });
    
    // the views dialog
    $('#views_dialog').dialog({
        bgiframe: true,
        autoOpen: false,
        height: 390,
        width: 625,
        modal: true,
        buttons: {
            'Save': function() {
                var views = [];
                var submit_structure = {};
                
                $('#views_table tr').each(function() {
                    views.push($(this).children('td:eq(1)').text());
                });

                submit_structure[($('#viewsitemid').val().split(/-/))[0]] = views;
                
                prauxn_home('set_views', {views: $.toJSON(submit_structure)}, 
                    function(data) {
                        // clear our datas
                        $('#viewsitemid').val('');
                    }
                );
                $('#views_container').html('<img id="views_busy" style="padding-top: 80px" src="/img/busy.gif"/>');
                $(this).dialog('close');
            },  
            'Cancel': function() {
                $('#views_container').html('<img id="views_busy" style="padding-top: 80px" src="/img/busy.gif"/>');
                $('#viewsitemid').val('');
                $(this).dialog('close');
            }   
        }
    });

    // the translate dialog
    $('#translate_dialog').dialog({
        bgiframe: true,
        autoOpen: false,
        height: 220,
        width: 625,
        modal: true,
        buttons: {
            'Yes': function() {
                $(this).dialog('close');
                
                // start translate.
                $.blockUI({
                    message: "Please wait while we translate your resume from " + default_lang_long + " to " + lang_long + ".",
                    css: { 
                        border: 'none', 
                        padding: '15px', 
                        'font-size': '16px',
                        'font-family': 'Helvetica, Arial, Sans-Serif',
                        backgroundColor: '#000', 
                        '-webkit-border-radius': '10px', 
                        '-moz-border-radius': '10px', 
                        opacity: .5, 
                        color: '#fff'
                    }
                });
                
                growl = false;
                
                setTimeout(function() {
                    $.unblockUI();
                }, 5000);
                
                // give it 30 seconds to complete before annoying them to death
                setTimeout(function() {
                    growl = true;
                }, 30000);
                
                var cbs = {};
                // get an obj of unique content blocks that need populatin'
                if (translate_all) {
                    $('.editable').each(function() {
                        var cbid = ($(this).attr('id').split(/-/))[0];
                        if (cbs[cbid]) {
                            cbs[cbid]++
                        } else {
                            cbs[cbid] = 1;
                        }
                    });
                } else {
                    $('.empty').each(function() {
                        var cbid = ($(this).attr('id').split(/-/))[0];
                        if (cbs[cbid]) {
                            cbs[cbid]++
                        } else {
                            cbs[cbid] = 1;
                        }
                    });
                }
                
                // reset this to a default value asap!
                translate_all = false;
                
                $.each(cbs, function(k, v) {
                    prauxn_home('get_content_block', { content_block: k, language: default_language }, function(data) {
                        // arrays to store stuff in.. so we can just call translate!
                        var tkeys = [];
                        var tvals = [];
                        
                        $.each(data, function(k, v) {
                            
                            if (k != 'success' && k != 'visible' && k != 'language' && k != 'content_item' && k != 'content_block') {
                                if (v != null && !v.match(/\[\//)) {
                                    tkeys.push(k);
                                    tvals.push(v)
                                } 
                            }
                        });
                        
                        // console.log("Calling $.translate([" + tvals + "], " + default_language + ", " + lang + ")!");
                        
                        // translate content block
                        $.translate(tvals, default_language, lang, {
                            stripWhitespace: true,
                            complete: function(translation) {
                                var i = 0;
                                var tblock = {
                                    content_block: data.content_block
                                };
                                
                                $.each(translation, function() {
                                    tblock[tkeys[i]] = this;
                                    i++;
                                });
                                
                                tblock['language'] = lang;
                                
                                
                                prauxn_home('edit_content_item', tblock, function(data) {
                                    // go through returned values from EditContentItem on this request.
                                    // if they're suggestions or comments they'll do nothing. 
                                    // this should be converted into a switch statement it looks like.
                                    if (data['Praux::Url::JSON::EditContentItem'] != undefined) {
                                        $.each(data['Praux::Url::JSON::EditContentItem'], function(i, n) {
                                            $('#' + n.html_id).text(n.display_value);
                                            $('#' + n.html_id).effect('highlight', {}, 1500);
                                        });
                                    }
                                });
                                
                                console.log("translation of " + data.content_block + " complete!");
                            }
                        });
                    });
                });
            },  
            'No': function() {
                $(this).dialog('close');
            }   
        }
    });

    // the confirm dialog
    $('#confirm_dialog').dialog({
        bgiframe: true,
        autoOpen: false,
        height: 220,
        width: 625,
        modal: true,
        buttons: {
            'Yes': function() {
                prauxn_home('remove_content_block', { content_block: ($('#confirmitemid').val().split(/-/))[0] }, 
                    function(data) {
                        $.each(data.removed_blocks, function(i, n) {
                            $('[id^=' + n + '-]').each(function() {
                                // if not this is grouping, go ahead and remove it ;)
                                if (!$(this).is('.grouping')) {
                                    if ($(this).parent('li').length > 0) {
                                        $(this).parent('li').remove();
                                    }
                                    if ($(this).parent('div.section').length > 0) {
                                        $(this).parent('div.section').remove();
                                    }
                                    $(this).remove();
                                }
                            });
                        });
                        
                        // clear our datas
                        $('#confirmitemid').val('');
                    }
                );
                $(this).dialog('close');
            },  
            'No': function() {
                $(this).dialog('close');
            }   
        }
    });

    // the section dialog
    $('#section_dialog').dialog({
        bgiframe: true,
        autoOpen: false,
        height: 290,
        width: 625,
        modal: true,
        buttons: {
            'Create': function() {
                prauxn_home('add_section', { 
                    format: $('#section_format').val(),
                    language: lang,
                    views: 'default',
                    body: $('#section_body').val()
                }, function(data) {
                    if ($('div.section').length > 0) {
                        $('div.section:first').before(data.rendered_section);
                    } else {
                        $('#sections').append(data.rendered_section);
                    }
                    
                    // install all our wicked handlers.
                    init_edit($('div.section:first'));
                    
                    // clear our datas
                    $('#section_body').val('');
                    
                    // set the order, so wysiwyg.
                    var ids = [];
                    $('.section').each(function(){
                        ids.push(($(this).attr('id').split(/-/))[0]);
                    });

                    prauxn_home('set_section_order', { order: ids }, function() {});
                });
                $(this).dialog('close');
            },  
            'Cancel': function() {
                $(this).dialog('close');
            }   
        }
    });
    
    $('#close_helper').click(function() {
        $('#helper_container').hide();
        $('#emblem').show();
    });
    
    $('#emblem').click(function() {
        if (active_user && $('#helper_container').length > 0) {
            $('#emblem').hide();
            $('#helper_container').show();
        } else {
            if (!$('#notice_container').is(':visible')) {
                ++pc_click_count;
                if (pc_click_count == 1) {
                    flash_notice("Hint:", "You can sign up for an account, and get your own resume at <a href='http://praux.com/'>http://praux.com</a>.");
                } else if (pc_click_count == 2) {
                    flash_notice("Hint:", "If you already have a resume, you can move it to a new .praux.com location by visiting it in your browser while you're logged in!");
                } else if (pc_click_count == 3) {
                    flash_notice("Hint:", "Go to <a href='" + app_base + "/edit/'>" + app_base + "/edit/</a> to edit this resume.");
                } else if (pc_click_count == 4) {
                    flash_notice("Hint:", "You can go to <a href='" + app_base + "/edit_resume/'>" + app_base + "/edit_resume/</a> too to edit your address, phone number, etc.");
                } else if (pc_click_count == 5) {
                    flash_notice("Seriously:", "Quit poking me!  Don't you have anything better to do?");
                }
            }
        }
    });
    
    $('#add_section').click(function() {
        $('#section_dialog').dialog('open');
    });
    
    $('#login_button').parents('form').submit(function() {
        $('#tried').val(tried);
        return true;
    });
    
    $('#add_section').hover(function() {
        $(this).css('background-color', '#eee');
    }, function() {
        $(this).css('background-color', '#fff');
    });
    
    if (active_user && is_mine && view == "edit") {
        init_edit();
        mode = 'edit';
        if ($('.empty').length > 0 && lang != default_language) {
            // we might need to do a lil translating for the user!
            $('#translate_dialog #translate_summary').html("We notice this resume has some portions that have not yet been translated to <em>" + 
                lang_long + "</em>, would you like us to use Google Translate&trade; to translate them from <em>" + default_lang_long +
                "</em> to <em>" + lang_long + "</em> for you?");
            $("#translate_dialog").dialog('open');
        } else if (lang != default_language) {
            // we might need to do a lil translating for the user!
            $('#retranslate').click(function() {
                console.log("retranslate clicked!");
                $('#translate_dialog #translate_summary').html("Just making sure, you want us to retranslate your resume into <em>" + 
                    lang_long + "</em> from <em>" + default_lang_long + "</em>?");
                translate_all = true;
                $("#translate_dialog").dialog('open');
                return false;
            });
        }
    } else if (active_user && !is_mine) {
        init_comment();
        mode = 'comment';
    }
    
    // ok.. if we have a functional url in there.. e.g. ".suggestions_for", we need to prase that out
    // here. AFTER INIT
    var location = document.location.toString();
    var match = location.match(/(.+?)\/[\.\#](\w+)\/([\w\-]*)\/?$/);
    
    if (match || tried) {
        // tried takes precedence over url-based directives..
        
        if (match) {
            var check = tried == true ? tried : match[2];
        } else {
            var check = tried;
        }
        
        switch(check) {
            case "suggestions_for":
                if (active_user && is_mine) {
                    init_edit();
                    mode = 'edit';
                    // nice array
                    var id_type = match[3].split(/-/);
                    var html_id = match[3];
                    prauxn_home('retrieve_suggestions', {
                            content_block: id_type[0],
                            suggested_attribute: id_type[1]
                        }, function(data) {
                            if (data['Praux::Url::JSON::RetrieveSuggestions'].length > 0) {
                                $('#suggestion_select').unbind('change').html('');
                                $.each(data['Praux::Url::JSON::RetrieveSuggestions'], function(i, n) {
                                    $('#suggestion_select').append('<option value="' + n.suggested_value + '" suggestion_id="' + n.suggestion + '">' +
                                        n.submitter_email + ' on ' + n.create_time + '</option>');
                                });

                                // change.
                                $('#suggestion_select').change(function() {
                                    $('#suggestion_final_value').val($(this).val());
                                    if ($(this).val()) {
                                        $('#suggestion_preview').html(diffString($('#' + html_id).html(), $(this).val()));
                                    } else {
                                        $('#suggestion_preview').html('');
                                    }

                                    if ($('#suggestion_select option').length == 0) {
                                        $('#suggestion_dialog').dialog('close');
                                        document.location = match[1] + "/";
                                    }
                                });

                                // keep it updated if the user decides to edit ;)
                                $('#suggestion_final_value').delayedObserver('0.5', function(v, ele) {
                                    $('#suggestion_preview').html(diffString($('#' + html_id).html(), ele.val()));
                                });

                                $("#suggestion_dialog").dialog('open');

                                // i wanted to copulate but i didn't want to populate...
                                $('#suggestion_select').change();
                            } else {
                                alert("No suggestions found!");
                                //document.location = match[1] + "/";
                            }

                        }
                    );
                }
            break
            case "edit_mode":
                $('#edit_mode').mousedown();
                $('#edit_mode').mouseup();
            break
            default:
                if (match) {
                    document.location = match[1] + "/";
                }
            break
        }
    }
});

function left_click_sort() {
    $('.editable').unbind('click').unbind('mouseover').unbind('mouseout');
    $('.editable').animate({ backgroundColor: '#fff' }, 100);
    $('.editable').css('cursor', 'move');
    // sortable sections
    $('#sections').sortable({
        handle: 'h2',
        axis: 'y',
        stop: function(e, ui) {
            // sections are easy.
            var ids = [];
            $('.section').each(function(){
                ids.push(($(this).attr('id').split(/-/))[0]);
            });
        
            prauxn_home('set_section_order', { order: ids }, function() {});
        }
    });
    
    $('div.grouping').sortable({
        handle: 'h3',
        axis: 'y',
        stop: function(e, ui) {
            var ids = [];
            $(this).children('div.container').each(function() {
                ids.push(($(this).attr('id').split(/-/))[0]);
            });
            
            prauxn_home('set_block_order', { order: ids }, function() {});
        }
    });
    
    $('ul.grouping').sortable({
        axis: 'y',
        stop: function(e, ui) {
            var ids = [];
            $(this).children('li').children('span.editable').each(function() {
                ids.push(($(this).attr('id').split(/-/))[0]);
            });
        
            prauxn_home('set_block_order', { order: ids }, function() {});
        }
    });
}

function is_a_section (e) {
    if (e.parent('div.section').length > 0) {
        return true;
    } else {
        return false;
    }
}

function section_id_format (e) {
    var format = e.parents('.section').attr('id');
    var id_format = format.split(/-/);
    return id_format;
}

function section_id (e) {
    var format = e.parents('.section').attr('id');
    var id_format = format.split(/-/);
    return id_format[0];
}

function section_format (e) {
    var format = e.parents('.section').attr('id');
    var id_format = format.split(/-/);
    return id_format[1];
}

// these dont need elements.
function init_subscribe () {
    mode_cleanup();

}

function init_talent_portfolios( ) {
    mode_cleanup();
    
}

function init_favorites () {
    mode_cleanup();
    
}

// this one does.
function init_edit (ele) {
    // riiight ;)
    if (ele) {
        if (!ele.is('.editable')) {
            ele = ele.find('.editable');
        }
    } else {
        // flash_notice('Edit Mode:', 'your resume is in edit mode, click an item to change its value right click for more options.');
        
        if (mode != 'edit') {
            $('#edit_extras').show();
        }
        
        ele = $('.editable');
    }
    
    $(ele).destroyContextMenu();
       
    // set up context menu
    ele.contextMenu({
        menu: 'editableMenu'
    }, function(action, el, pos) {
        if (action == "edit") {
            if ($(el).attr('origvalue')) {
                $('#value_dialog #itemvalue').val($(el).attr('origvalue'));
            } else {
                $('#value_dialog #itemvalue').val($(el).text());
            }
            $('#value_dialog #itemid').val($(el).attr('id'));
            $('#ui-dialog-title-value_dialog').text("Editing Item");
            $('#value_label').text("New Item Value");
            $('#value_form').attr('action', 'edit_content_item');
            $('#value_dialog').dialog('open');
        } else if (action == "add") {
            var submit_data = {};
            submit_data['parent'] = ($(el).attr('id').split(/-/))[0]
        
            // inherit section format if we're adding to the section.
            if (is_a_section(el)) {
                submit_data['format'] = section_format(el);
            } else if (section_format(el) == "generic_nobullets") {
                submit_data['format'] = "generic_nobullets";
            } else {
                submit_data['format'] = 'generic';
            }
        
            // always specify the default view
            submit_data['views'] = "default";
        
            // specify the language please
            submit_data['language'] = lang;
        
            prauxn_home('add_content_block', submit_data,
                function(data) {
                    if ($(el).parent().is('li')) {
                        // sub-items :D.
                        var parent = $(el).parent();
                        if (parent.children('ul').length > 0) {
                            parent.children('ul').append(data.rendered_block);
                        } else {
                            var parent_id = (parent.children('span').attr('id').split(/-/))[0];
                            parent.append('<ul id="' + parent_id + '-children" class="grouping">' + data.rendered_block + '</ul>')
                        }
                    
                        // re initialize edit mode (go one up from here)!
                        init_edit($(el).parent());
                    } else {
                        if ($(el).siblings('ul').length > 0) {
                            //alert("appending last ul");
                            $(el).siblings('ul:last').append(data.rendered_block);
                        } else {
                            if ($(el).siblings('p').length > 0) {
                                //alert("Appending siblings p");
                                $(el).closest('div').append('<ul class="grouping">' + data.rendered_block + "</ul>");
                            } else if ($(el).siblings('div.section').length > 0) {
                                //alert("appending siblings div.section");
                                $(el).siblings('div').append('<ul class="grouping">' + data.rendered_block + "</ul>");
                            } else if ($(el).siblings('div.job_data').length == 1) {
                                //alert("appending one sibling div");
                                if ($(el).siblings('div').children('ul.grouping').length > 0) {
                                    $(el).siblings('div').children('ul.grouping').append(data.rendered_block);
                                } else {
                                    $(el).siblings('div').append('<ul class="grouping">' + data.rendered_block + '</ul>');
                                }
                            } else if ($(el).parent('p.orgrole').length > 0) {
                                //alert("appending orgrole div");
                                if ($(el).closest('div.job_data').children('ul.grouping').length > 0) {
                                    $(el).closest('div.job_data').children('ul.grouping').append(data.rendered_block);
                                } else {
                                    $(el).closest('div.job_data').append('<ul class="grouping">' + data.rendered_block + '</ul>');
                                }
                            } else {
                                //alert("appending (else) closest div.section");
                                $(el).closest('div.section').children('div.grouping').append(data.rendered_block);
                            }
                        }
                    
                        // re initialize edit mode (go one up from here)!
                        init_edit($(el).closest('div.section'));

                    }
                }
            );
        } else if (action == "delete") {
            $("#confirm_dialog #confirmage").html("Are you sure you want to remove the block containing: <em>" + $(el).html() + "</em> and all of its subcontent?");
            $("#confirm_dialog #confirmitemid").val($(el).attr('id'));
            $("#confirm_dialog").dialog('open');
        } else if (action == "views") {
            // consistency is a bitch.. but im too lazy to go back..
            $("#viewsitemid").val($(el).attr('id'));
            prauxn_home('get_views', { content_block: ($(el).attr('id').split(/-/))[0] }, 
                function(data) {
                    // clear out our container..
                    $('#views_container').html('<table id="views_table" cellspacing="0" cellpadding="0" style="padding-top:8px;border:0;width:95%"></table>');
                    var vt = $('#views_container').find('#views_table');
                    
                    if (data.views && data.views.length > 0) {                    
                        $.each(data.views, function(i, n) {
                            vt.append("<tr><td width='25%'>&nbsp</td><td align='left' width='45%'>" + n + "</td><td align='left' class='view_delete'>" + 
                                      "<img src='/img/del_16x16.png'/></td><td width='25%'>&nbsp</td></tr>");
                        });
                    }
                    
                    $('#views_container').append('<table id="add_view_table" style="padding-top:8px;border:0;width:95%"></table>');
                    
                    $('#add_view_table').append("<tr><td width='25%'>&nbsp</td><td align='left'><input type='text' class='text ui-widget-content ui-corner-all' id='view_input'/></td>" + 
                                                 "<td align='left'><input class='ui-widget-content ui-corner-all' type='button' value='Add' id='view_add_button'/></td>" + 
                                                 "<td width='25%'>&nbsp</td></tr>");
                       
                    $("#view_add_button").unbind('click');
                    $("#view_add_button").click(function() {
                        if ($('#view_input').val().match(/^[\w\-\.]+$/)) {
                            if ($('#view_input').val() == "rr" || $('#view_input').val() == "resume") {
                                alert("Cannot create a view called 'resume' or 'rr'");
                            } else {
                                $("#views_table").append("<tr><td width='25%'>&nbsp</td><td align='left' width='45%'>" + 
                                          $('#view_input').val() + "</td><td align='left' class='view_delete'>" + 
                                          "<img src='/img/del_16x16.png'/></td><td width='25%'>&nbsp</td></tr>");
                                $('#view_input').val('');
                                stripe_n_click();
                            }
                        } else {
                            alert("Illegal characters!  View names must be alphanumeric, -, and .!");
                        }
                    });
                    
                    stripe_n_click(); 
                }
            );
            $("#views_dialog").dialog('open');
        } else if (action == "suggestions") {
            // nice array
            var id_type = $(el).attr('id').split(/-/);
            var html_id = $(el).attr('id');
            
            prauxn_home('retrieve_suggestions', {
                    content_block: id_type[0],
                    suggested_attribute: id_type[1]
                }, function(data) {
                    if (data['Praux::Url::JSON::RetrieveSuggestions'].length > 0) {
                        $('#suggestion_select').unbind('change').html('');
                        $.each(data['Praux::Url::JSON::RetrieveSuggestions'], function(i, n) {
                            $('#suggestion_select').append('<option value="' + n.suggested_value + '" suggestion_id="' + n.suggestion + '">' +
                                n.submitter_email + ' on ' + n.create_time + '</option>');
                        });
                        
                        // change.
                        $('#suggestion_select').change(function() {
                            $('#suggestion_final_value').val($(this).val());
                            if ($(this).val()) {
                                $('#suggestion_preview').html(diffString($('#' + html_id).html(), $(this).val()));
                            } else {
                                $('#suggestion_preview').html('');
                            }
                            
                            if ($('#suggestion_select option').length == 0) {
                                $('#suggestion_dialog').dialog('close');
                            }
                        });
                        
                        // keep it updated if the user decides to edit ;)
                        $('#suggestion_final_value').delayedObserver('0.5', function(v, ele) {
                            $('#suggestion_preview').html(diffString($('#' + html_id).html(), ele.val()));
                        });
                        
                        $("#suggestion_dialog").dialog('open');
                        
                        // i wanted to copulate but i didn't want to populate...
                        $('#suggestion_select').change();
                    } else {
                        alert("No suggestions found!");
                    }

                }
            );
        }
    });
    
    // only do this if we didn't explicitly enable left click sort.
    if (lcs == false) {
        left_click_edit(ele);
    } else {
        left_click_sort(ele);
    }
}

function stripe_n_click () {
    $('#views_table .view_delete').unbind('click');
    $('#views_table .view_delete').click(function() {
        //if ($(this).parent('tr').find(':contains(default)').length == 0) {
        $(this).parent('tr').fadeOut('250', function() {
            $(this).remove();
            stripe_n_click();
        });
       //}
    });

    $('#views_table tr').removeClass('odd even');
    $('#views_table tr:odd').addClass('odd');
    $('#views_table tr:even').addClass('even');
}

function left_click_suggest () {
    var ele = $('.editable');
    
    $(ele).css('cursor', '');
    
    $(ele).unbind('click').unbind('mouseover').unbind('mouseout');
    $('#sections').sortable('destroy');
    $('div.grouping').sortable('destroy');
    $('ul.grouping').sortable('destroy');
    ele.click(function() {
        if ($(this).attr('origvalue')) {
            $('#value_dialog #itemvalue').val($(this).attr('origvalue'));
        } else {
            $('#value_dialog #itemvalue').val($(this).text());
        } 
        $('#value_dialog #itemid').val($(this).attr('id'));
        $('#ui-dialog-title-value_dialog').text("Suggest Item Value");
        $('#value_label').text("Suggested Value");
        $('#value_form').attr('action', 'add_suggestion');
        $('#value_dialog').dialog('open');
    }).enableContextMenu();
}

function left_click_edit (ele) {
    if (!ele) {
        ele = $('.editable');
    }
    
    // preload this image once and for all!
    var praux_tip_img = new Image(142, 140);
    praux_tip_img.src = "/img/praux_tip.png";
    
    $(ele).css('cursor', '');
    
    $(ele).unbind('click').unbind('mouseover').unbind('mouseout');
    $('#sections').sortable('destroy');
    $('div.grouping').sortable('destroy');
    $('ul.grouping').sortable('destroy');
    ele.click(function() {
        if ($(this).attr('origvalue')) {
            $('#itemvalue').val($(this).attr('origvalue'));
        } else {
            $('#itemvalue').val($(this).text());
        }
        $('#itemid').val($(this).attr('id'));
        $('#value_form').attr('action', 'edit_content_item');
        $('#value_dialog').dialog('open');
    }).mouseover(function() {
        $(this).animate({ backgroundColor: '#ddd' }, 250);
    }).mouseout(function() {
        $(this).animate({ backgroundColor: '#fff' }, 250);
    }).tooltip(
        {
            showURL: false,
            track: true,
            bodyHandler: function() {
                // tool tip lotto...
                var tool_tip;
                //if ((Math.floor(Math.random() * 50 + 1)) % 5) {
                    tool_tip = 'Click To Edit, Right Click For More Options';
                //} else {
                //    tool_tip = '<img src="http://praux.com/img/praux_tip.png" height="153px" width="150px" alt="Prauxfessional Advice!" style="float:left;"/>';
                //    tool_tip += 'And now for something completely different!';
                //}
                return (tool_tip);
            }
        }
    ).enableContextMenu();
}

function mode_cleanup () {
    clear_notice();
    if (mode == "edit") {
        $('#edit_extras').hide();
    }
    
    mode = "view";
    
    $('.editable').css('cursor', '');
    $('.editable').destroyContextMenu();
    $('.editable').unbind('click').unbind('mouseover').unbind('mouseout');
    $('#sections').sortable('destroy');
    $('div.grouping').sortable('destroy');
    $('ul.grouping').sortable('destroy');
}

function init_comment (ele) {
    // always do this.
    mode_cleanup();
    
    if (ele) {
        ele = ele.find('.editable');
    } else {
        ele = $('.editable');
    }

    // clean up other modes potential hooks..
    $(ele).destroyContextMenu();
    
    // set up context menu
    ele.contextMenu({
        menu: 'commentMenu'
    }, function(action, el, pos) {
        if (action == "suggest") {
            if ($(el).attr('origvalue')) {
                $('#value_dialog #itemvalue').val($(el).attr('origvalue'));
            } else {
                $('#value_dialog #itemvalue').val($(el).text());
            }
            $('#value_dialog #itemid').val($(el).attr('id'));
            $('#ui-dialog-title-value_dialog').text("Suggest Item Value");
            $('#value_label').text("Suggested Value");
            $('#value_form').attr('action', 'add_suggestion');
            $('#value_dialog').dialog('open');
        } else if (action == "score-up") {
            prauxn_home('vote', {
                content_block: ($(el).attr('id').split(/-/))[0],
                html_id: $(el).attr('id'),
                vote: 'up'
            }, function(data) {
                $.each(data['Praux::Url::JSON::Vote'], function(i, n) {
                    $('#' + n.html_id).effect('highlight', {color: '#ecfef1'}, 1500);
                });
            });
        } else if (action == "score-down") {
            prauxn_home('vote', {
                content_block: ($(el).attr('id').split(/-/))[0],
                html_id: $(el).attr('id'),
                vote: 'down'
            }, function(data) {
                $.each(data['Praux::Url::JSON::Vote'], function(i, n) {
                    $('#' + n.html_id).effect('highlight', {color: '#fef1ec'}, 1500);
                });
            });;
        } else if (action == "comment") {
            $('#value_dialog #itemvalue').val();
            $('#value_dialog #itemid').val($(el).attr('id'));
            $('#ui-dialog-title-value_dialog').text("Add Comment");
            $('#value_form').attr('action', 'comment');
            $('#value_label').text('Leave Feedback');
            $('#value_dialog').dialog('open');
        }
    });
    left_click_suggest();
}

function clear_notice () {
    $('#notice_word').html();
    $('#notice_body').html();
    $('#notice_container').hide();
}

function set_notice (word, body) {
    $('#notice_word').html(word);
    $('#notice_body').html(body);
    $('#notice_container').fadeIn(250);
}

function flash_notice (word, body) {
    set_notice(word, body);
    setTimeout(function() {
        $('#notice_container').fadeOut(250);
    }, 5000);
}

function clear_error () {
    $('#error_word').html();
    $('#error_body').html();
    $('#error_container').hide();
}

function set_error (word, body) {
    $('#error_word').html(word);
    $('#error_body').html(body);
    $('#error_container').fadeIn(250);
}

function flash_error (word, body) {
    set_error(word, body);
    setTimeout(function() {
        $('#error_container').fadeOut(250);
    }, 7000);
}

// generic ajax function
function prauxn_home (func, data, callback) {
    $.ajax({
        url: "/json/" + func + "/",
        type: "POST",
        dataType: "json",
        data: data,
        success: function(data, status) {
            if (data.success == 0) {
                flash_error('Error:', data.error);
            } else {
                callback(data, status);
                if (data['general_message']) {
                    if (growl == true) {
                        $.jGrowl(data['general_message']);
                    }
                }
                if (debug) {
                    $.each(data, function(k, v) {
                        if (k.match(/^Praux::Url/)) {
                            $.each(v, function() {
                                if (growl == true) {
                                    if (this.message != undefined) {
                                        $.jGrowl("[debug] " + k + ": " + this.message);
                                    }
                                
                                    if (this.error != undefined) {
                                        $.jGrowl("[debug] " + k + ": " + this.error);
                                    }
                                }
                            });
                        }
                    });
                }
            }
        },
        error: function(xht, status, error) {
            flash_error('Error:', 'Problem communicating with server (' + status + ')');
        }
    });
}
