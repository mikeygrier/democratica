define([
    'jquery',
    'underscore',
    'backbone',
    'websocket',
    'bootstrap',
    'bootstrap-dialog'
], function($, _, Backbone, WebSocket, Bootstrap, BootstrapDialog) {
    var OAuth2 = Backbone.View.extend({
        events: {
            'click .add-client': 'addClient',
            'click #create-client': 'createClient',
            'click .modify-client': 'getClient',
            'click #save-client': 'saveClient',
            'click #remove-client': 'removeClient',
            'change #meritcommons-certificate': 'changeCert',
            'click .add-scope': 'addScope',
            'click #create-scope': 'createScope',
            'click .modify-scope': 'getScope',
            'click #save-scope': 'saveScope',
            'click #remove-scope': 'removeScope',
        },

        el: $('#content-wrapper'),

        initialize: function() {
            $('#modifyClient').on('hide.bs.modal', function(e) {
                $('#modify-common-name').val('');
                $('#modify-description').html('');
                $('#modify-callback-url').val('');
                $('#modify-unique-id').val('');
                $('.modify-error').hide();
                $('.modify-success').hide();
            });

            $('#modifyScope').on('hide.bs.modal', function(e) {
                $('#scope-modify-common-name').val('');
                $('#scope-modify-description').html('');
                $('#scope-modify-unique-id').val('');
                $('.scope-modify-error').hide();
                $('.scope-modify-success').hide();
            });

            $('#addScope').on('hide.bs.modal', function(e) {
                $('#scope-common-name').val('');
                $('#scope-description').val('');
                $('.scope-create-error').hide();
                $('#create-scope').prop('disabled', false);
            });
        },

        addClient: function(ev) {
            $('#addClient').modal('show');
        },

        changeCert: function(ev) {
            var $checkbox = $(ev.target);
            var $certificate = $('#certificate');

            if ($checkbox.is(':checked')) {
                $certificate.parent().hide();
            } else {
                $certificate.parent().show();
            }
        },

        createClient: function(ev) {
            var self = this;

            var data = {
                common_name: $('#common-name').val(),
                meritcommons_certificate: $('#meritcommons-certificate').is(':checked') ? 1 : 0,
                certificate: $('#certificate').val(),
                description: $('#description').val(),
                callback_url: $('#callback-url').val(),
            };

            if (!data.common_name) {
                $('.create-error').html('Error: No <strong>common name</strong> provided.').show();
            } else if (!data.meritcommons_certificate && !data.certificate) {
                $('.create-error').html('Error: No <strong>certificate</strong> provided.').show();
            } else if (!data.description) {
                $('.create-error').html('Error: No <strong>description</strong> provided.').show();
            } else if (!data.callback_url || !(/^(([^:\/?#]+):)?(\/\/([^\/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?/.exec(data.callback_url))) {
                $('.create-error').html('Error: ' + (data.callback_url ? 'Invalid' : 'No') + ' <strong>callback url</strong> provided.').show();
            } else {
                $('#create-client').hide();
                $('.create-client').hide();
                $('.creating-client').show();

                MeritCommons.WebSocket.conn.send('oauth2 create_client ' + JSON.stringify(data), {
                    callback: function(e, data) {
                        try {
                            data = JSON.parse(data.body);
                            self.afterCreateClient(data);
                        } catch (e) {
                            $('.create-error').html('Error: ' + data.body).show();
                            $('.creating-client').hide();
                            $('#create-client').show();
                            $('.create-client').show();
                        }
                    }
                });
            }
        },

        afterCreateClient: function(client) {
            var self = this;

            if (client.success) {
                $('.creating-client').hide();
                $('.client-secret').html(client.client_secret);
                $('.client-secret-placeholder').show();

                self.SHOWING_SECRET = true;

                $('#addClient').on('hide.bs.modal', function(e) {
                    if (self.SHOWING_SECRET) {
                        e.preventDefault();
                        BootstrapDialog.confirm({
                            title: 'Client Secret',
                            type: BootstrapDialog.TYPE_DANGER,
                            message: "Are you sure you have copied the secret down in a safe place. Once you close this window you can never retrieve it again.",
                            closeByBackdrop: false, 
                            callback: function(result) {
                                if (result) {
                                    self.SHOWING_SECRET = false;
                                    $('#addClient').off('hide.bs.modal');
                                    $('#addClient').modal('hide');
                                    $('.client-secret-placeholder').hide();
                                    $('.client-secret').html('');
                                    $('.create-error').hide();
                                    $('.create-client').show();
                                    $('#create-client').show();
                                }
                            }
                        });
                    }
                });

                var modify_time = new Date(client.modify_time * 1000);
                var modify_time_string = modify_time.getFullYear() + '-' + (modify_time.getMonth() + 1 < 10 ? '0' : '') + (modify_time.getMonth() + 1) + '-' + modify_time.getDate() + ' ' + 
                                         modify_time.getHours() + ':' + modify_time.getMinutes() + ':' + modify_time.getSeconds();

                $('.no-clients').hide();
                $('#oauth2-clients').find('tbody').append('<tr id="' + client.unique_id + '">' +
                    '<td class="table-common-name">' + client.common_name + '</td>' +
                    '<td class="table-thumbprint">' + client.thumbprint + '</td>' +
                    '<td class="table-unique-id">' + client.unique_id + '</td>' +
                    '<td class="table-modify-time">' + modify_time_string + '</td>' +
                    '<td><a class="btn btn-warning modify-client">Modify</a></td></td>' +
                '</tr>');

                $('#common-name').val('');
                $('#meritcommons-certificate').prop('checked', true);
                $('#certificate').val('').parent().hide();
                $('#description').val('');
                $('#callback-url').val('');
            } else {
                if (client.error) {
                    $('.create-error').html('Error: ' + client.error).show();
                } else {
                    $('.create-error').html('Error: Unknown error. Please contact an administrator.').show();
                }

                $('.creating-client').hide();
                $('#create-client').show();
                $('.create-client').show();
            }
        },

        getClient: function(ev) {
            var self = this;
            var data = {
                unique_id: $(ev.target).closest('tr').attr('id'),
            };

            MeritCommons.WebSocket.conn.send('oauth2 get_client ' + JSON.stringify(data), {
                callback: function(e, data) {
                    try {
                        data = JSON.parse(data.body);
                        self.afterGetClient(data);
                    } catch (e) {
                        console.log('Error: ' + data.body);
                    }
                }
            });
        },

        afterGetClient: function(client) {
            $('#modify-common-name').val(client.common_name);
            $('#modify-description').html(client.description);
            $('#modify-callback-url').val(client.callback_url);
            $('#modify-unique-id').val(client.unique_id);
            $('#modifyClient').modal('show');
        },

        saveClient: function(ev) {
            var self = this;

            var data = {
                common_name: $('#modify-common-name').val(),
                description: $('#modify-description').val(),
                callback_url: $('#modify-callback-url').val(),
                unique_id: $('#modify-unique-id').val(),
            };

            if (!data.common_name) {
                $('.modify-error').html('Error: No <strong>common name</strong> provided.').show();
            } else if (!data.description) {
                $('.modify-error').html('Error: No <strong>description</strong> provided.').show();
            } else if (!data.callback_url || !(/^(([^:\/?#]+):)?(\/\/([^\/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?/.exec(data.callback_url))) {
                $('.modify-error').html('Error: ' + (data.callback_url ? 'Invalid' : 'No') + ' <strong>callback url</strong> provided.').show();
            } else {
                $('#save-client').prop('disabled', true);

                MeritCommons.WebSocket.conn.send('oauth2 modify_client ' + JSON.stringify(data), {
                    callback: function(e, data) {
                        try {
                            data = JSON.parse(data.body);
                            self.afterSaveClient(data);
                        } catch (e) {
                            $('.modify-error').html('Error: ' + data.body).show();
                            $('#save-client').prop('disabled', false);
                        }
                    }
                });
            }
        },

        afterSaveClient: function(client) {
            if (client.success) {
                $('#modify-error').hide();
                $('.modify-success').fadeIn().delay(15000).fadeOut();
                $('#save-client').prop('disabled', false);

                var $client = $('#' + client.unique_id);

                $client.find('.table-common-name').html(client.common_name);

                var modify_time = new Date(client.modify_time * 1000);
                var modify_time_string = modify_time.getFullYear() + '-' + (modify_time.getMonth() + 1 < 10 ? '0' : '') + (modify_time.getMonth() + 1) + '-' + modify_time.getDate() + ' ' + 
                                         modify_time.getHours() + ':' + modify_time.getMinutes() + ':' + modify_time.getSeconds();

                $client.find('.table-modify-time').html(modify_time_string);
            } else {
                $('.modify-error').html('Error: ' + client.error).show();
                $('#save-client').prop('disabled', false);
            }
        },

        removeClient: function(ev) {
            var self = this;

            var unique_id = $('#modify-unique-id').val();
            var common_name = $('#' + unique_id).find('.table-common-name').html();

            var data = {
                unique_id: unique_id,
            }           

            var dialog = BootstrapDialog.show({
                title: 'Delete Client',
                type: BootstrapDialog.TYPE_DANGER,
                message: '<p>Are you sure you want to remove <strong>' + common_name + '</strong>? It can never be recovered.</p>' +
                         '<p>Please type the name of the client below to proceed:</p>' +
                         '<input type="text" class="form-control" id="delete-common-name">',
                closeByBackdrop: false, 
                buttons: [
                    {
                        label: 'Cancel',
                        action: function(dialog) {
                            dialog.close();
                        }
                    },
                    {
                        label: 'Delete',
                        cssClass: 'btn-danger delete-client',
                        disabled: true,
                        action: function(dialog) {
                            if ($('#delete-common-name').val().toLowerCase() == common_name.toLowerCase()) {
                                dialog.close();
                                dialog.$modalFooter.find('.delete-client').prop('disabled', true);
                                $('#modifyClient').modal('hide');

                                MeritCommons.WebSocket.conn.send('oauth2 remove_client ' + JSON.stringify(data), {
                                    callback: function(e, data) {
                                        try {
                                            data = JSON.parse(data.body);
                                            self.afterRemoveClient(data);
                                        } catch (e) {
                                            $('.delete-success').html('Error: ' + data.body).fadeIn();
                                        }
                                    }
                                });
                            } else {
                                console.log(dialog.$modalBody.append());
                            }
                        },
                    }, 
                ],
            });

            dialog.$modalFooter.find('.delete-client').prop('disabled', true);

            dialog.$modalBody.find('#delete-common-name').on('keyup', function() {
                if ($(this).val().toLowerCase() == common_name.toLowerCase()) {
                    dialog.$modalFooter.find('.delete-client').prop('disabled', false);
                } else {
                    dialog.$modalFooter.find('.delete-client').prop('disabled', true);
                }
            });
        },

        afterRemoveClient: function(client) {
            if (client.success) {
                var common_name = $('#' + client.unique_id).find('.table-common-name').html();
                $('.delete-success').html('Succesfully deleted ' + common_name).fadeIn().delay(15000).fadeOut();
                $('#' + client.unique_id).remove();

                if ($('#oauth2-clients').find('tr').length < 2) {
                    $('.no-clients').show();   
                }
            } else {
                $('.delete-success').html('Error: ' + client.error).fadeIn();
            }
        },

        addScope: function(ev) {
            $('#addScope').modal('show');
        },

        createScope: function(ev) {
            var self = this;

            var data = {
                common_name: $('#scope-common-name').val(),
                description: $('#scope-description').val(),
            };

            if (!data.common_name) {
                $('.scope-create-error').html('Error: No <strong>common name</strong> provided.').show();
            } else if (!data.description) {
                $('.scope-create-error').html('Error: No <strong>description</strong> provided.').show();
            } else {
                 $('#create-scope').prop('disabled', true);

                MeritCommons.WebSocket.conn.send('oauth2 create_scope ' + JSON.stringify(data), {
                    callback: function(e, data) {
                        try {
                            data = JSON.parse(data.body);
                            self.afterCreateScope(data);
                        } catch (e) {
                            $('.scope-create-error').html('Error: ' + data.body).show();
                            $('#create-scope').prop('disabled', false);
                        }
                    }
                });
            }
        },

        afterCreateScope: function(scope) {
            var self = this;

            if (scope.success) {
                $('#addScope').modal('hide');
                $('.scope-create-success').html('Succesfully created ' + scope.common_name).fadeIn().delay(15000).fadeOut();

                var modify_time = new Date(scope.modify_time * 1000);
                var modify_time_string = modify_time.getFullYear() + '-' + (modify_time.getMonth() + 1 < 10 ? '0' : '') + (modify_time.getMonth() + 1) + '-' + modify_time.getDate() + ' ' + 
                                         modify_time.getHours() + ':' + modify_time.getMinutes() + ':' + modify_time.getSeconds();

                $('.no-scopes').hide();
                $('#oauth2-scopes').find('tbody').append('<tr id="' + scope.unique_id + '">' +
                    '<td class="table-common-name">' + scope.common_name + '</td>' +
                    '<td class="table-description">' + scope.description + '</td>' +
                    '<td class="table-modify-time">' + modify_time_string + '</td>' +
                    '<td><a class="btn btn-warning modify-scope">Modify</a></td></td>' +
                '</tr>');

                $('#scope-common-name').val('');
                $('#scope-description').val('');
            } else {
                if (scope.error) {
                    $('.scope-create-error').html('Error: ' + scope.error).show();
                } else {
                    $('.scope-create-error').html('Error: Unknown error. Please contact an administrator.').show();
                }
                $('#create-scope').prop('disabled', false);
            }
        },

        getScope: function(ev) {
            var self = this;
            
            var $scope = $(ev.target).closest('tr');
            var scope = {
                unique_id: $scope.attr('id'),
                common_name: $scope.find('.table-common-name').html(),
                description: $scope.find('.table-description').html(),
            };

            $('#scope-modify-common-name').val(scope.common_name);
            $('#scope-modify-description').html(scope.description);
            $('#scope-modify-unique-id').val(scope.unique_id);
            $('#modifyScope').modal('show');
        },

        saveScope: function(ev) {
            var self = this;

            var data = {
                unique_id: $('#scope-modify-unique-id').val(),
                common_name: $('#scope-modify-common-name').val(),
                description: $('#scope-modify-description').val(),
            };

            if (!data.common_name) {
                $('.scope-modify-error').html('Error: No <strong>common name</strong> provided.').show();
            } else if (!data.description) {
                $('.scope-modify-error').html('Error: No <strong>description</strong> provided.').show();
            } else {
                $('#save-scope').prop('disabled', true);

                MeritCommons.WebSocket.conn.send('oauth2 modify_scope ' + JSON.stringify(data), {
                    callback: function(e, data) {
                        try {
                            data = JSON.parse(data.body);
                            self.afterSaveScope(data);
                        } catch (e) {
                            $('.scope-modify-error').html('Error: ' + data.body).show();
                            $('#save-scope').prop('disabled', false);
                        }
                    }
                });
            }
        },

        afterSaveScope: function(scope) {
            if (scope.success) {
                $('.scope-modify-error').hide();
                $('.scope-modify-success').fadeIn().delay(15000).fadeOut();
                $('#save-scope').prop('disabled', false);

                var $scope = $('#' + scope.unique_id);

                $scope.find('.table-common-name').html(scope.common_name);
                $scope.find('.table-description').html(scope.description);

                var modify_time = new Date(scope.modify_time * 1000);
                var modify_time_string = modify_time.getFullYear() + '-' + (modify_time.getMonth() + 1 < 10 ? '0' : '') + (modify_time.getMonth() + 1) + '-' + modify_time.getDate() + ' ' + 
                                         modify_time.getHours() + ':' + modify_time.getMinutes() + ':' + modify_time.getSeconds();

                $scope.find('.table-modify-time').html(modify_time_string);
            } else {
                $('.scope-modify-error').html('Error: ' + scope.error).show();
                $('#save-scope').prop('disabled', false);
            }
        },

        removeScope: function(ev) {
            var self = this;

            var unique_id = $('#scope-modify-unique-id').val();
            var common_name = $('#' + unique_id).find('.table-common-name').html();

            var data = {
                unique_id: unique_id,
            }           

            MeritCommons.WebSocket.conn.send('oauth2 remove_scope ' + JSON.stringify(data), {
                callback: function(e, data) {
                    try {
                        data = JSON.parse(data.body);
                        self.afterRemoveScope(data);
                    } catch (e) {
                        $('#modifyScope').modal('hide');
                        $('.scope-delete-success').html('Error: ' + data.body).fadeIn();
                    }
                }
            });
        },

        afterRemoveScope: function(scope) {
            if (scope.success) {
                var common_name = $('#' + scope.unique_id).find('.table-common-name').html();
                $('.scope-delete-success').html('Succesfully deleted ' + common_name).fadeIn().delay(15000).fadeOut();
                $('#' + scope.unique_id).remove();

                if ($('#oauth2-scopes').find('tr').length < 2) {
                    $('.no-scopes').show();   
                }
            } else {
                $('.scope-delete-success').html('Error: ' + scope.error).fadeIn();
            }
            $('#modifyScope').modal('hide');
        },
    });
    
    return OAuth2;
});