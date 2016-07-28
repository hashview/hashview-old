/**
 * @fileOverview bs_grid is a jQuery datagrid plugin based on Twitter Bootstrap.
 *               <p>License MIT
 *               <br />Copyright Christos Pontikis <a href="http://www.pontikis.net">http://www.pontikis.net</a>
 *               <br />Project page <a href="http://www.pontikis.net/labs/bs_grid/">http://www.pontikis.net/labs/bs_grid/</a>
 * @version 0.9.2 (28 May 2014)
 * @author Christos Pontikis http://www.pontikis.net
 * @requires jquery >= 1.8, twitter bootstrap >= 2, bs_pagination plugin, jQuery UI sortable (optional), jui_filter_rules plugin >= 1.0.4 (optional)
 */

/**
 * See <a href="http://jquery.com">http://jquery.com</a>.
 * @name $
 * @class
 * See the jQuery Library  (<a href="http://jquery.com">http://jquery.com</a>) for full details.  This just
 * documents the function and classes that are added to jQuery by this plug-in.
 */

/**
 * See <a href="http://jquery.com">http://jquery.com</a>
 * @name fn
 * @class
 * See the jQuery Library  (<a href="http://jquery.com">http://jquery.com</a>) for full details.  This just
 * documents the function and classes that are added to jQuery by this plug-in.
 * @memberOf $
 */

/**
 * Pseudo-Namespace containing bs_grid private methods (for documentation purposes)
 * @name _private_methods
 * @namespace
 */

"use strict";
(function($) {

    var pluginName = "bs_grid",
        pluginGivenOptions = "bs_grid_given_options",
        pluginStatus = "bs_grid_status";

    // public methods
    var methods = {

        /**
         * @lends $.fn.bs_grid
         */
        init: function(options) {

            var elem = this;

            return this.each(function() {

                /**
                 * store given options on first launch (in new object - no reference)
                 */
                if(typeof  elem.data(pluginGivenOptions) === "undefined") {
                    elem.data(pluginGivenOptions, $.extend(true, {}, options));
                }

                /**
                 * settings and defaults
                 * settings modification will affect elem.data(pluginName) and vice versa
                 */
                var settings = elem.data(pluginName);
                if(typeof settings === "undefined") {
                    var bootstrap_version = "3";
                    if(options.hasOwnProperty("bootstrap_version") && options["bootstrap_version"] == "2") {
                        bootstrap_version = "2";
                    }
                    var defaults = methods.getDefaults.call(elem, bootstrap_version);
                    // deep merge ('true' arg) is required, as there are object attibutes (paginationOptions, filterOptions)
                    settings = $.extend(true, {}, defaults, options);
                } else {
                    settings = $.extend(true, {}, settings, options);
                }
                elem.data(pluginName, settings);

                // initialize plugin status
                if(typeof  elem.data(pluginStatus) === "undefined") {
                    elem.data(pluginStatus, {});
                }

                if(!settings.row_primary_key) {
                    settings.selected_ids = [];
                } else {
                    switch(settings.rowSelectionMode) {
                        case "single":
                            if(settings.selected_ids.length > 1) {
                                settings.selected_ids = [];
                            }
                            break;
                        case false:
                            settings.selected_ids = [];
                            break;
                    }
                }
                var container_id = elem.attr("id");

                // apply container style
                elem.removeClass().addClass(settings.containerClass);

                // bind events
                elem.unbind("onCellClick").bind("onCellClick", settings.onCellClick);
                elem.unbind("onRowClick").bind("onRowClick", settings.onRowClick);
                elem.unbind("onDatagridError").bind("onDatagridError", settings.onDatagridError);
                elem.unbind("onDebug").bind("onDebug", settings.onDebug);
                elem.unbind("onDisplay").bind("onDisplay", settings.onDisplay);

                // initialize plugin html
                var tools_id = create_id(settings.tools_id_prefix, container_id),
                    columns_list_id = create_id(settings.columns_list_id_prefix, container_id),
                    default_columns_list = "",
                    sorting_list_id = create_id(settings.sorting_list_id_prefix, container_id),
                    default_sorting_list = "",
                    sorting_radio_name = create_id(settings.sorting_radio_name_prefix, container_id) + "_",
                    startPos, newPos,
                    selected_rows_id = create_id(settings.selected_rows_id_prefix, container_id),
                    selection_list_id = create_id(settings.selection_list_id_prefix, container_id),
                    table_container_id = create_id(settings.table_container_id_prefix, container_id),
                    table_id = create_id(settings.table_id_prefix, container_id),
                    no_results_id = create_id(settings.no_results_id_prefix, container_id),
                    filter_toggle_id = create_id(settings.filter_toggle_id_prefix, container_id),
                    custom_html1_id = create_id(settings.custom_html1_id_prefix, container_id),
                    custom_html2_id = create_id(settings.custom_html2_id_prefix, container_id),
                    pagination_id = create_id(settings.pagination_id_prefix, container_id),
                    filter_container_id = create_id(settings.filter_container_id_prefix, container_id),
                    filter_rules_id = create_id(settings.filter_rules_id_prefix, container_id),
                    filter_tools_id = create_id(settings.filter_tools_id_prefix, container_id),
                    elem_html = "", tools_html = "";

                // create basic html structure ---------------------------------
                elem_html += '<div id="' + tools_id + '" class="' + settings.toolsClass + '"></div>';

                elem_html += '<div id="' + table_container_id + '" class="' + settings.dataTableContainerClass + '">';
                elem_html += '<table id="' + table_id + '" class="' + settings.dataTableClass + '"></table>';
                elem_html += '</div>';

                elem_html += '<div id="' + no_results_id + '" class="' + settings.noResultsClass + '">' + rsc_bs_dg.no_records_found + '</div>';

                if(settings.customHTMLelementID1) {
                    elem_html += '<div id="' + custom_html1_id + '"></div>';
                }

                elem_html += '<div id="' + pagination_id + '"></div>';

                if(settings.customHTMLelementID2) {
                    elem_html += '<div id="' + custom_html2_id + '"></div>';
                }

                if(settings.useFilters) {
                    elem_html += '<div id="' + filter_container_id + '" class="' + settings.filterContainerClass + '">';

                    elem_html += '<div id="' + filter_rules_id + '"></div>';

                    elem_html += '<div id="' + filter_tools_id + '" class="' + settings.filterToolsClass + '">';
                    elem_html += '<button class="' + settings.filterApplyBtnClass + '">' + rsc_bs_dg.filters_apply + '</button>';
                    elem_html += '<button class="' + settings.filterResetBtnClass + '">' + rsc_bs_dg.filters_reset + '</button>';

                    elem_html += '</div>';
                }

                elem_html += '</div>';

                elem.html(elem_html);
                $("#" + no_results_id).hide();

                var elem_tools = $("#" + tools_id),
                    elem_table = $("#" + table_id),
                    elem_pagination = $("#" + pagination_id);

                // create toolbar ----------------------------------------------
                // columns list
                tools_html += '<div class="btn-group pull-right">';

                tools_html += '<button type="button" class="' + settings.columnsListLaunchButtonClass + '" data-toggle="dropdown" title="' + rsc_bs_dg.columns + '">';
                tools_html += '<span class="' + settings.columnsListLaunchButtonIconClass + '"></span>';
                tools_html += '<span class="caret"></span>';
                tools_html += '</button>';

                tools_html += '<ul id="' + columns_list_id + '" class="' + settings.columnsListClass + '">';

                var col_name, col_checked,
                    col_list_len = 0;
                for(var i in settings.columns) {
                    if(column_is_function(settings.columns[i])) {
                        continue;
                    }
                    col_list_len++;
                    col_name = get_column_header(settings.columns[i]);
                    col_checked = column_is_visible(settings.columns[i]) ? " checked" : "";
                    default_columns_list += '<li><a href="javascript:void(0);">' +
                        '<label class="' + settings.columnsListLabelClass + '">' +
                        '<input type="checkbox" class="' + settings.columnsListCheckClass + '"' + col_checked + '> ' + col_name +
                        '</label>' +
                        '</a></li>';
                }
                default_columns_list += '<li class="not-sortable ' + settings.columnsListDividerClass + '"></li>';

                var row_index_checked = settings.showRowNumbers ? " checked" : "";
                default_columns_list += '<li class="not-sortable columns-li-padding"><label class="' + settings.columnsListLabelClass + '"><input type="checkbox" class="' + settings.columnsListCheckClass + '"' + row_index_checked + '>&nbsp;' + rsc_bs_dg.columns_show_row_numbers + '</label></li>';
                default_columns_list += '<li class="not-sortable ' + settings.columnsListDividerClass + '"></li>';
                default_columns_list += '<li class="not-sortable columns-li-padding"><button class="' + settings.columnsListDefaultButtonClass + '">' + rsc_bs_dg.columns_default + '</button></li>';

                //save default columns list
                if(typeof elem.data(pluginStatus)["default_columns_list"] === "undefined") {
                    elem.data(pluginStatus)["default_columns_list"] = default_columns_list;
                }

                tools_html += default_columns_list;

                tools_html += '</ul>';

                tools_html += '</div>';

                // sorting list ------------------------------------------------
                tools_html += '<div class="btn-group pull-right">';

                tools_html += '<button type="button" class="btn btn-default dropdown-toggle" data-toggle="dropdown" title="' + rsc_bs_dg.sorting + '">';
                tools_html += '<span class="' + settings.sortingListLaunchButtonIconClass + '"></span>';
                tools_html += '<span class="caret"></span>';
                tools_html += '</button>';

                tools_html += '<ul id="' + sorting_list_id + '" class="dropdown-menu dropdown-menu-right">';

                for(var i in settings.sorting) {
                    var sort_name = get_sorting_name(settings.sorting[i]),
                        checked_asc = settings.sorting[i]["order"] == "ascending" ? " checked" : "",
                        checked_desc = settings.sorting[i]["order"] == "descending" ? " checked" : "",
                        checked_none = settings.sorting[i]["order"] == "none" ? " checked" : "";
                    default_sorting_list += '<li><a href="javascript:void(0);">' +
                        '<label class="' + settings.sortingLabelCheckboxClass + '"><input type="radio" name="' + sorting_radio_name + i + '"' + checked_asc + '>' + rsc_bs_dg.sort_ascending + '</label>' +
                        '<label class="' + settings.sortingLabelCheckboxClass + '"><input type="radio" name="' + sorting_radio_name + i + '"' + checked_desc + '>' + rsc_bs_dg.sort_descending + '</label>' +
                        '<label class="' + settings.sortingLabelCheckboxClass + '"><input type="radio" name="' + sorting_radio_name + i + '"' + checked_none + '>' + rsc_bs_dg.sort_none + '</label>' +
                        '<span class="' + settings.sortingNameClass + '">' + sort_name + '</span>' +
                        '</a></li>';
                }
                default_sorting_list += '<li class="not-sortable ' + settings.columnsListDividerClass + '"></li>';
                default_sorting_list += '<li class="not-sortable columns-li-padding"><button class="' + settings.columnsListDefaultButtonClass + '">' + rsc_bs_dg.sorting_default + '</button></li>';

                //save default columns list
                if(typeof elem.data(pluginStatus)["default_sorting_list"] === "undefined") {
                    elem.data(pluginStatus)["default_sorting_list"] = default_sorting_list;
                }

                tools_html += default_sorting_list;

                tools_html += '</ul>';

                tools_html += '</div>';

                // selection list ----------------------------------------------
                if(settings.row_primary_key &&
                    (settings.rowSelectionMode == "single" || settings.rowSelectionMode == "multiple")) {
                    tools_html += '<div class="btn-group pull-right">';

                    tools_html += '<button type="button" class="btn btn-default dropdown-toggle" data-toggle="dropdown" title="' + rsc_bs_dg.select + '">';
                    tools_html += '<span class="' + settings.selectButtonIconClass + '"></span>';
                    tools_html += '<span id="' + selected_rows_id + '" class="' + settings.selectedRowsClass + '">' + settings.selected_ids.length + '</span>';
                    tools_html += '<span class="caret"></span>';
                    tools_html += '</button>';

                    tools_html += '<ul id="' + selection_list_id + '" class="dropdown-menu dropdown-menu-right">';

                    if(settings.rowSelectionMode == "multiple") {
                        tools_html += '<li><a href="javascript:void(0);">' + rsc_bs_dg.select_all_in_page + '</a></li>';
                        tools_html += '<li><a href="javascript:void(0);">' + rsc_bs_dg.deselect_all_in_page + '</a></li>';
                        tools_html += '<li><a href="javascript:void(0);">' + rsc_bs_dg.select_inverse_in_page + '</a></li>';
                        tools_html += '<li class="not-sortable ' + settings.columnsListDividerClass + '"></li>';
                    }

                    tools_html += '<li><a href="javascript:void(0);">' + rsc_bs_dg.deselect_all + '</a></li>';

                    tools_html += '</ul>';

                    tools_html += '</div>';
                }

                // filter toggle button ----------------------------------------
                if(settings.useFilters) {
                    tools_html += '<button id="' + filter_toggle_id + '" class="btn btn-default pull-right" title="' + rsc_bs_dg.filters + '"><span class="' + settings.filterToggleButtonIconClass + '"></span></button>';
                }

                elem_tools.html(tools_html);

                // initialize grid ---------------------------------------------
                var grid_init = methods.displayGrid.call(elem, false);

                /**
                 * EVENTS ******************************************************
                 */

                //TOOLS - columns list -----------------------------------------
                var elem_columns_list = $("#" + columns_list_id);

                // Prevent closing on click
                elem_columns_list.click(function(e) {
                    e.stopPropagation();
                });

                // show - hide column
                elem_columns_list.off("click", "input[type=checkbox]").on("click", "input[type=checkbox]", function() {

                    var col_index = $($("#" + columns_list_id + " li input[type=checkbox]")).index(this);
                    if(col_index < col_list_len) {

                        var checked_columns = $("#" + columns_list_id + " li").not(".not-sortable").find("input[type=checkbox]:checked").length;
                        if(checked_columns == 1) {
                            $("#" + columns_list_id + " li input[type=checkbox]:checked:first").slice(0, col_list_len).attr("disabled", true);
                        } else {
                            $("#" + columns_list_id + " li input[type=checkbox]").slice(0, col_list_len).removeAttr("disabled");
                        }
                        set_column_visible(settings.columns[col_index], $(this).is(":checked"));

                    } else {
                        // show - hide row index
                        settings.showRowNumbers = $(this).is(":checked");
                    }
                    methods.displayGrid.call(elem, false);
                });

                // change column index
                if(settings.useSortableLists) {
                    if(col_list_len > 2) {
                        elem_columns_list.sortable({
                            items: "li:not(.not-sortable)",
                            start: function(event, ui) {
                                startPos = ui.item.index();
                            },
                            stop: function(event, ui) {
                                newPos = ui.item.index();
                                if(newPos !== startPos) {
                                    array_move(settings.columns, startPos, newPos);
                                    methods.displayGrid.call(elem, false);
                                }
                            }
                        });
                    }
                }

                // display default columns
                elem_columns_list.off("click", "li:last button").on("click", "li:last button", function() {

                    for(var i in elem.data(pluginGivenOptions)["columns"]) {
                        settings.columns[i] = $.extend(true, {}, elem.data(pluginGivenOptions)["columns"][i]);
                    }

                    var checked = elem.data(pluginGivenOptions)["showRowNumbers"];
                    if(typeof checked === "undefined") {
                        checked = methods.getDefaults.call(elem, settings.bootstrap_version)["showRowNumbers"];
                    }
                    settings.showRowNumbers = checked;

                    elem_columns_list.html(elem.data(pluginStatus)["default_columns_list"]);

                    methods.displayGrid.call(elem, false);
                });

                // TOOLS - sorting list ----------------------------------------
                var elem_sorting_list = $("#" + sorting_list_id),
                    sort_len = settings.sorting.length;

                // Prevent closing on click
                elem_sorting_list.click(function(e) {
                    e.stopPropagation();
                });

                // change sorting type
                elem_sorting_list.off("click", "input[type=radio]").on("click", "input[type=radio]", function() {
                    var radio_index = $($("#" + sorting_list_id + " li input[type=radio]")).index(this),
                        sorting_index = Math.floor(radio_index / 3),
                        sorting_type = "";
                    switch(radio_index % 3) {
                        case 0:
                            sorting_type = "ascending";
                            break;
                        case 1:
                            sorting_type = "descending";
                            break;
                        case 2:
                            sorting_type = "none";
                            break;
                    }
                    if(settings.sorting[sorting_index]["order"] != sorting_type) {
                        settings.sorting[sorting_index]["order"] = sorting_type;
                        methods.displayGrid.call(elem, false);
                    }
                });

                // change sorting index
                if(settings.useSortableLists) {
                    if(sort_len > 2) {
                        elem_sorting_list.sortable({
                            items: "li:not(.not-sortable)",
                            start: function(event, ui) {
                                startPos = ui.item.index();
                            },
                            stop: function(event, ui) {
                                newPos = ui.item.index();
                                if(newPos !== startPos) {
                                    array_move(settings.sorting, startPos, newPos);
                                    methods.displayGrid.call(elem, false);
                                }
                            }
                        });
                    }
                }

                // display default sorting
                elem_sorting_list.off("click", "li:last button").on("click", "li:last button", function() {

                    for(var i in elem.data(pluginGivenOptions)["sorting"]) {
                        settings.sorting[i] = $.extend(true, {}, elem.data(pluginGivenOptions)["sorting"][i]);
                    }
                    elem_sorting_list.html(elem.data(pluginStatus)["default_sorting_list"]);

                    methods.displayGrid.call(elem, false);
                });

                // row selection -----------------------------------------------
                if(settings.row_primary_key &&
                    (settings.rowSelectionMode == "single" || settings.rowSelectionMode == "multiple")) {

                    var row_prefix_len = (table_id + "_tr_").length;

                    // click on row
                    elem_table.off("click", "tbody tr").on("click", "tbody tr", function() {

                        var row_id = parseInt($(this).attr("id").substr(row_prefix_len)),
                            row_status,
                            idx = methods.selectedRows.call(elem, "selected_index", row_id);

                        if(idx > -1) {
                            methods.selectedRows.call(elem, "remove_id", idx);
                            methods.selectedRows.call(elem, "mark_deselected", row_id);
                            row_status = "deselected";
                        } else {
                            if(settings.rowSelectionMode == "single") {
                                methods.selectedRows.call(elem, "clear_all_ids");
                                methods.selectedRows.call(elem, "mark_page_deselected");
                            }
                            methods.selectedRows.call(elem, "add_id", row_id);
                            methods.selectedRows.call(elem, "mark_selected", row_id);
                            row_status = "selected";
                        }

                        // update selected rows counter
                        methods.selectedRows.call(elem, "update_counter");

                        elem.triggerHandler("onRowClick", {row_id: row_id, row_status: row_status});
                    });

                    // selection list
                    var elem_selection_list = $("#" + selection_list_id);

                    elem_selection_list.off("click", "li").on("click", "li", function() {
                        var sel_index = $(this).index();

                        if(settings.rowSelectionMode == "single") {
                            methods.selectedRows.call(elem, "clear_all_ids");
                            methods.selectedRows.call(elem, "mark_page_deselected");
                        } else if(settings.rowSelectionMode == "multiple") {

                            var selector_table_tr = "#" + table_id + " tbody tr",
                                row_prefix_len = (table_id + "_tr_").length,
                                row_id, idx;
                            switch(sel_index) {
                                case 0:
                                    $(selector_table_tr).each(function() {
                                        row_id = parseInt($(this).attr("id").substr(row_prefix_len));
                                        idx = methods.selectedRows.call(elem, "selected_index", row_id);
                                        if(idx == -1) {
                                            methods.selectedRows.call(elem, "add_id", row_id);
                                        }
                                    });
                                    methods.selectedRows.call(elem, "mark_page_selected");
                                    break;
                                case 1:
                                    $(selector_table_tr).each(function() {
                                        row_id = parseInt($(this).attr("id").substr(row_prefix_len));
                                        idx = methods.selectedRows.call(elem, "selected_index", row_id);
                                        if(idx > -1) {
                                            methods.selectedRows.call(elem, "remove_id", idx);
                                        }
                                    });
                                    methods.selectedRows.call(elem, "mark_page_deselected");
                                    break;
                                case 2:
                                    $(selector_table_tr).each(function() {
                                        row_id = parseInt($(this).attr("id").substr(row_prefix_len));
                                        idx = methods.selectedRows.call(elem, "selected_index", row_id);
                                        if(idx > -1) {
                                            methods.selectedRows.call(elem, "remove_id", idx);
                                        } else {
                                            methods.selectedRows.call(elem, "add_id", row_id);
                                        }
                                    });
                                    methods.selectedRows.call(elem, "mark_page_inversed");
                                    break;
                                case 4:
                                    methods.selectedRows.call(elem, "clear_all_ids");
                                    methods.selectedRows.call(elem, "mark_page_deselected");
                                    break;
                            }
                        }

                        // update selected rows counter
                        methods.selectedRows.call(elem, "update_counter");

                    });

                }

                // click on cell -----------------------------------------------
                elem_table.off("click", "tbody tr td").on("click", "tbody tr td", function() {
                    var col_index = $(this).index();
                    var row_index = $(this).parent("tr").index();
                    elem.triggerHandler("onCellClick", {col: col_index, row: row_index});
                });

                // simple columns sorting --------------------------------------
                elem_table.off("click", "thead th").on("click", "thead th", function() {

                    var th_index = $(this).index(),
                        th_text = $(this).text();

                    if(settings.showRowNumbers) {
                        if(th_index == 0) {
                            return false;
                        } else {
                            th_index--;
                        }
                    }

                    // get column field
                    var visible_index = -1, th_field = "", th_sortable = false;
                    for(var i in settings.columns) {
                        if(column_is_visible(settings.columns[i])) {
                            visible_index++;
                            if(visible_index == th_index) {
                                th_field = settings.columns[i].field;
                                th_sortable = column_is_sortable(settings.columns[i]);
                                break;
                            }
                        }
                    }

                    if(!th_sortable) {
                        return false;
                    }

                    if(th_field) {

                        // get sorting order for this field (if any)
                        var current_order = "", new_order;
                        for(var i in settings.sorting) {
                            if(settings.sorting[i].field == th_field) {
                                current_order = settings.sorting[i].order;
                                break;
                            }
                        }

                        switch(current_order) {
                            case "ascending":
                                new_order = "descending";
                                break;
                            case "descending":
                                new_order = "none";
                                break;
                            case "none":
                                new_order = "ascending";
                                break;
                            default:
                                new_order = "ascending";
                        }

                        settings.sorting = [
                            {
                                sortingName: th_text,
                                field: th_field,
                                order: new_order
                            }
                        ];

                        // update sorting list
                        var checked_asc = new_order == "ascending" ? " checked" : "",
                            checked_desc = new_order == "descending" ? " checked" : "",
                            checked_none = new_order == "none" ? " checked" : "";
                        var sorting_list_html = '<li><a href="javascript:void(0);">' +
                            '<label class="' + settings.sortingLabelCheckboxClass + '"><input type="radio" name="' + sorting_radio_name + '0' + '"' + checked_asc + '>' + rsc_bs_dg.sort_ascending + '</label>' +
                            '<label class="' + settings.sortingLabelCheckboxClass + '"><input type="radio" name="' + sorting_radio_name + '0' + '"' + checked_desc + '>' + rsc_bs_dg.sort_descending + '</label>' +
                            '<label class="' + settings.sortingLabelCheckboxClass + '"><input type="radio" name="' + sorting_radio_name + '0' + '"' + checked_none + '>' + rsc_bs_dg.sort_none + '</label>' +
                            '<span class="' + settings.sortingNameClass + '">' + th_text + '</span>' +
                            '</a></li>';

                        sorting_list_html += '<li class="not-sortable ' + settings.columnsListDividerClass + '"></li>';
                        sorting_list_html += '<li class="not-sortable columns-li-padding"><button class="' + settings.columnsListDefaultButtonClass + '">' + rsc_bs_dg.sorting_default + '</button></li>';
                        elem_sorting_list.html(sorting_list_html);

                        // display grid
                        methods.displayGrid.call(elem, false);

                    }

                });

                // PAGINATION --------------------------------------------------
                $.when(grid_init).then(function(data, textStatus, jqXHR) {

                    var total_rows = data["total_rows"];

                    var pagination_options = settings.paginationOptions,
                        bs_grid_pagination_options = {
                            // defined by bs_grid
                            currentPage: settings.pageNum,
                            rowsPerPage: settings.rowsPerPage,
                            maxRowsPerPage: settings.maxRowsPerPage,
                            totalPages: Math.ceil(total_rows / settings.rowsPerPage),
                            totalRows: total_rows,
                            bootstrap_version: settings.bootstrap_version,

                            onChangePage: function(event, params) {
                                settings.pageNum = params.currentPage;
                                settings.rowsPerPage = params.rowsPerPage;
                                methods.displayGrid.call(elem, false);
                            }
                        };
                    $.extend(pagination_options, bs_grid_pagination_options);
                    elem_pagination.bs_pagination(pagination_options);

                    // custom html ---------------------------------------------
                    // (not an event, but page renders better displaying custom html after grid rendering)
                    if(settings.customHTMLelementID1) {
                        $("#" + custom_html1_id).html($("#" + settings.customHTMLelementID1).html());
                    }

                    if(settings.customHTMLelementID2) {
                        $("#" + custom_html2_id).html($("#" + settings.customHTMLelementID2).html());
                    }

                });

                // FILTERS -----------------------------------------------------
                if(settings.useFilters) {

                    var elem_filter_toggle = $("#" + filter_toggle_id),
                        elem_filter_container = $("#" + filter_container_id),
                        elem_filter_rules = $("#" + filter_rules_id),
                        elem_filter_tools = $("#" + filter_tools_id);

                    // initialize jui_filter_rules plugin ----------------------
                    var filter_options = settings.filterOptions,
                        bs_grid_internal_filter_options = {
                            bootstrap_version: settings.bootstrap_version,
                            onValidationError: function(event, data) {
                                elem.triggerHandler("onDatagridError", data);
                            },
                            onSetRules: function() {
                            }
                        };
                    filter_options = $.extend({}, filter_options, bs_grid_internal_filter_options);
                    elem_filter_rules.jui_filter_rules(filter_options);

                    if(filter_options.filter_rules.length > 0) {
                        elem_filter_container.show();
                    } else {
                        elem_filter_container.hide();
                    }

                    /* filter toogle */
                    elem_tools.off("click", "#" + filter_toggle_id).on("click", "#" + filter_toggle_id, function() {

                        if(elem_filter_container.is(":visible")) {
                            elem_filter_container.slideUp();
                            if(settings.filterOptions.filter_rules.length > 0) {
                                // mark filter toggle as active
                                elem_filter_toggle.addClass(settings.filterToggleActiveClass);
                            }
                        } else {
                            elem_filter_container.slideDown();
                            // mark filter toggle as inactive
                            elem_filter_toggle.removeClass(settings.filterToggleActiveClass);
                        }

                    });

                    /* filter tools */
                    elem_filter_tools.off("click", "button").on("click", "button", function() {

                        var btn_index = $(this).index(),
                            a_rules = elem_filter_rules.jui_filter_rules("getRules", 0, []);

                        if(a_rules == false) {
                            return false;
                        }

                        switch(btn_index) {
                            case 0:
                                //elem_filter_rules.jui_filter_rules("markAllRulesAsApplied");
                                settings.filterOptions.filter_rules = a_rules;
                                // Reset selected rows
                                settings.selected_ids = [];
                                break;
                            case 1:
                                elem_filter_rules.jui_filter_rules("clearAllRules");
                                settings.filterOptions.filter_rules = [];
                                break;
                        }
                        settings.pageNum = 1;
                        methods.displayGrid.call(elem, true);

                    });

                }

            });
        },

        /**
         * Get plugin version
         * @returns {string}
         */
        getVersion: function() {
            return "0.9.2";
        },

        /**
         * Get default values
         * @example $(element).bs_grid("getDefaults", "3");
         * @return {Object}
         */
        getDefaults: function(bootstrap_version) {
            var default_settings = {
                pageNum: 1,
                rowsPerPage: 10,
                maxRowsPerPage: 100,
                row_primary_key: "",
                rowSelectionMode: "single", // "multiple", "single", false
                selected_ids: [],

                /**
                 * MANDATORY PROPERTIES: field
                 * UNIQUE PROPERTIES: field
                 * {field: "customer_id", header: "Code", visible: "no", is_function: "no", "headerClass": "th_code hidden-xs", "dataClass": "td_code hidden-xs"},
                 */
                columns: [],

                /**
                 * MANDATORY PROPERTIES: field, order
                 * UNIQUE PROPERTIES: field
                 * order is one of "ascending", "descending", "none"
                 * {sortingName: "Code", field: "customer_id", order: "none"},
                 */
                sorting: [],

                /**
                 * See bs_pagination plugin documentation
                 */
                paginationOptions: {
                    containerClass: "well pagination-container",
                    visiblePageLinks: 5,
                    showGoToPage: true,
                    showRowsPerPage: true,
                    showRowsInfo: true,
                    showRowsDefaultInfo: true,
                    disableTextSelectionInNavPane: true
                }, // "currentPage", "rowsPerPage", "maxRowsPerPage", "totalPages", "totalRows", "bootstrap_version", "onChangePage" will be ignored

                /**
                 * See jui_filter_rules plugin documentation
                 */
                filterOptions: {
                    filters: [],
                    filter_rules: []
                }, // "bootstrap_version", "onSetRules", "onValidationError" will be ignored

                useFilters: true,
                showRowNumbers: false,
                showSortingIndicator: true,
                useSortableLists: true,
                customHTMLelementID1: "",
                customHTMLelementID2: "",

                /* STYLES ----------------------------------------------------*/
                bootstrap_version: "3",

                // bs 3
                containerClass: "grid_container",
                noResultsClass: "alert alert-warning no-records-found",

                toolsClass: "tools",

                columnsListLaunchButtonClass: "btn btn-default dropdown-toggle",
                columnsListLaunchButtonIconClass: "glyphicon glyphicon-th",
                columnsListClass: "dropdown-menu dropdown-menu-right",
                columnsListLabelClass: "columns-label",
                columnsListCheckClass: "col-checkbox",
                columnsListDividerClass: "divider",
                columnsListDefaultButtonClass: "btn btn-primary btn-xs btn-block",

                sortingListLaunchButtonIconClass: "glyphicon glyphicon-sort",
                sortingLabelCheckboxClass: "radio-inline",
                sortingNameClass: "sorting-name",

                selectButtonIconClass: "glyphicon  glyphicon-check",
                selectedRowsClass: "selected-rows",

                filterToggleButtonIconClass: "glyphicon glyphicon-filter",
                filterToggleActiveClass: "btn-info",

                sortingIndicatorAscClass: "glyphicon glyphicon-chevron-up text-muted",
                sortingIndicatorDescClass: "glyphicon glyphicon-chevron-down text-muted",

                dataTableContainerClass: "table-responsive",
                dataTableClass: "table table-bordered table-hover",
                commonThClass: "th-common",
                selectedTrClass: "warning",

                filterContainerClass: "well filters-container",
                filterToolsClass: "",
                filterApplyBtnClass: "btn btn-primary btn-sm filters-button",
                filterResetBtnClass: "btn btn-default btn-sm filters-button",

                // prefixes
                tools_id_prefix: "tools_",
                columns_list_id_prefix: "columns_list_",
                sorting_list_id_prefix: "sorting_list_",
                sorting_radio_name_prefix: "sort_radio_",
                selected_rows_id_prefix: "selected_rows_",
                selection_list_id_prefix: "selection_list_",
                filter_toggle_id_prefix: "filter_toggle_",

                table_container_id_prefix: "tbl_container_",
                table_id_prefix: "tbl_",

                no_results_id_prefix: "no_res_",

                custom_html1_id_prefix: "custom1_",
                custom_html2_id_prefix: "custom2_",

                pagination_id_prefix: "pag_",
                filter_container_id_prefix: "flt_container_",
                filter_rules_id_prefix: "flt_rules_",
                filter_tools_id_prefix: "flt_tools_",

                // misc
                debug_mode: "no",

                // events
                onCellClick: function() {
                },
                onRowClick: function() {
                },
                onDatagridError: function() {
                },
                onDebug: function() {
                },
                onDisplay: function() {
                }
            };

            if(bootstrap_version == "2") {
                default_settings.bootstrap_version = "2";
                // bs 2
                default_settings.columnsListLaunchButtonIconClass = "icon-th";
                default_settings.sortingListLaunchButtonIconClass = "icon-resize-vertical";
                default_settings.sortingLabelCheckboxClass = "radio inline";
                default_settings.selectButtonIconClass = "icon-check";
                default_settings.filterToggleButtonIconClass = "icon-filter";
                default_settings.filterToggleActiveClass = "btn-info";

                default_settings.sortingIndicatorAscClass = "icon-chevron-up muted";
                default_settings.sortingIndicatorDescClass = "icon-chevron-down muted";

                default_settings.dataTableContainerClass = "table-responsive";
                default_settings.dataTableClass = "table table-bordered table-hover";

                default_settings.filterApplyBtnClass = "btn btn-primary filters-button ";
                default_settings.filterResetBtnClass = "btn btn-default filters-button";
            }

            return default_settings;
        },

        /**
         * Get any option set to plugin using its name (as string)
         *
         * @example $(element).bs_grid("getOption", some_option);
         * @param {String} opt
         * @return {*}
         */
        getOption: function(opt) {
            var elem = this;
            return elem.data(pluginName)[opt];
        },

        /**
         * Get all options
         * @example $(element).bs_grid("getAllOptions");
         * @return {*}
         */
        getAllOptions: function() {
            var elem = this;
            return elem.data(pluginName);
        },

        /**
         * Destroy plugin
         * @example $(element).bs_grid("destroy");
         */
        destroy: function() {
            var elem = this,
                container_id = elem.attr("id"),
                pagination_container_id = create_id(methods.getOption.call(elem, "pagination_id_prefix"), container_id),
                filter_rules_id = create_id(methods.getOption.call(elem, "filter_rules_id_prefix"), container_id);

            $("#" + pagination_container_id).removeData();
            $("#" + filter_rules_id).removeData();
            elem.removeData();
        },

        /**
         *
         * @param {string} action
         * @param {int} id the id or its (zero based) index in selected IDs
         * @returns {*}
         */
        selectedRows: function(action, id) {
            var elem = this,
                container_id = elem.attr("id"),
                s = methods.getAllOptions.call(elem),
                table_id = create_id(methods.getOption.call(elem, "table_id_prefix"), container_id),
                selectedTrClass = methods.getOption.call(elem, "selectedTrClass"),
                selector_table_tr = "#" + table_id + " tbody tr",
                table_tr_prefix = "#" + table_id + "_tr_";

            switch(action) {
                case "get_ids":
                    return s.selected_ids;
                    break;
                case "clear_all_ids":
                    s.selected_ids = [];
                    break;
                case "update_counter":
                    var selected_rows_id = create_id(methods.getOption.call(elem, "selected_rows_id_prefix"), container_id);
                    $("#" + selected_rows_id).text(s.selected_ids.length);
                    break;
                case "selected_index":
                    return $.inArray(id, s.selected_ids);
                    break;
                case "add_id":
                    s.selected_ids.push(id);
                    break;
                case "remove_id":
                    s.selected_ids.splice(id, 1);
                    break;
                case "mark_selected":
                    $(table_tr_prefix + id).addClass(selectedTrClass);
                    break;
                case "mark_deselected":
                    $(table_tr_prefix + id).removeClass(selectedTrClass);
                    break;
                case "mark_page_selected":
                    $(selector_table_tr).addClass(selectedTrClass);
                    break;
                case "mark_page_deselected":
                    $(selector_table_tr).removeClass(selectedTrClass);
                    break;
                case "mark_page_inversed":
                    $(selector_table_tr).toggleClass(selectedTrClass);
                    break;
            }

        },

        /**
         * Set a class to page column
         * @example $(element).bs_grid("setPageColClass", 1, "headerClass", "dataClass");
         * @param {Number} col_index
         * @param {String} headerClass
         * @param {String} dataClass
         */
        setPageColClass: function(col_index, headerClass, dataClass) {
            var elem = this,
                container_id = elem.attr("id"),
                data_table_selector = "#" + create_id(methods.getOption.call(elem, "table_id_prefix"), container_id);

            if(headerClass !== "") {
                $(data_table_selector + " th").eq(col_index).addClass(headerClass);
            }
            if(dataClass !== "") {
                $(data_table_selector + " tr").each(function() {
                    $(this).find("td").eq(col_index).addClass(dataClass);
                });
            }

        },

        /**
         * Set a class to page column
         * @example $(element).bs_grid("removePageColClass", 1, "headerClass", "dataClass");
         * @param {Number} col_index
         * @param {String} headerClass
         * @param {String} dataClass
         */
        removePageColClass: function(col_index, headerClass, dataClass) {
            var elem = this,
                container_id = elem.attr("id"),
                data_table_selector = "#" + create_id(methods.getOption.call(elem, "table_id_prefix"), container_id);

            $(data_table_selector + " th").eq(col_index).removeClass(headerClass);
            $(data_table_selector + " tr").each(function() {
                $(this).find("td").eq(col_index).removeClass(dataClass);
            });

        },

        displayGrid: function(refresh_pag) {

            var elem = this,
                container_id = elem.attr("id"),
                s = methods.getAllOptions.call(elem),

                table_id = create_id(s.table_id_prefix, container_id),
                elem_table = $("#" + table_id),
                no_results_id = create_id(s.no_results_id_prefix, container_id),
                elem_no_results = $("#" + no_results_id),
                filter_rules_id = create_id(s.filter_rules_id_prefix, container_id),
                pagination_id = create_id(s.pagination_id_prefix, container_id),
                elem_pagination = $("#" + pagination_id),
                err_msg;

            // fetch page data and display datagrid
            var res = $.ajax({
                type: "POST",
                url: s.ajaxFetchDataURL,
                data: {
                    page_num: s.pageNum,
                    rows_per_page: s.rowsPerPage,
                    columns: s.columns,
                    sorting: s.sorting,
                    filter_rules: s.filterOptions.filter_rules,
                    debug_mode: s.debug_mode
                },
                dataType: "json",
                success: function(data) {
                    var server_error, filter_error, row_primary_key, total_rows, page_data, page_data_len, v,
                        columns = s.columns,
                        col_len = columns.length,
                        column, c;

                    server_error = data["error"];
                    if(server_error != null) {
                        err_msg = "ERROR: " + server_error;
                        elem.html('<span style="color: red;">' + err_msg + '</span>');
                        elem.triggerHandler("onDatagridError", {err_code: "server_error", err_description: server_error});
                        $.error(err_msg);
                    }

                    if(s.useFilters) {
                        var elem_filter_rules = $("#" + filter_rules_id);
                        filter_error = data["filter_error"];
                        if(filter_error["error_message"] != null) {
                            elem_filter_rules.jui_filter_rules("markRuleAsError", filter_error["element_rule_id"], true);
                            elem_filter_rules.triggerHandler("onValidationError", {err_code: "filter_validation_server_error", err_description: filter_error["error_message"]});
                            $.error(filter_error["error_message"]);
                        }
                    }

                    total_rows = data["total_rows"];
                    page_data = data["page_data"];
                    page_data_len = page_data.length;

                    elem.data(pluginStatus)["total_rows"] = total_rows;

                    row_primary_key = s.row_primary_key;

                    if(s.debug_mode == "yes") {
                        elem.triggerHandler("onDebug", {debug_message: data["debug_message"]});
                    }

                    // replace null with empty string
                    if(page_data_len > 0) {
                        for(v = 0; v < page_data_len; v++) {
                            for(c = 0; c < col_len; c++) {
                                column = columns[c];
                                if(column_is_visible(column)) {
                                    if(page_data[v][column["field"]] == null) {
                                        page_data[v][column["field"]] = '';
                                    }
                                }
                            }
                        }
                    }

                    // create data table
                    var pageNum = parseInt(s.pageNum),
                        rowsPerPage = parseInt(s.rowsPerPage),
                        sortingIndicator,
                        row_id_html, i, row, tbl_html, row_index,
                        offset = ((pageNum - 1) * rowsPerPage);

                    tbl_html = '<thead>';
                    row_id_html = (row_primary_key ? ' id="' + table_id + '_tr_0"' : '');
                    tbl_html += '<tr' + row_id_html + '>';

                    if(s.showRowNumbers) {
                        tbl_html += '<th class="' + s.commonThClass + '">' + rsc_bs_dg.row_index_header + '</th>';
                    }

                    for(i in s.columns) {
                        if(column_is_visible(s.columns[i])) {
                            sortingIndicator = "";
                            if(s.showSortingIndicator) {
                                var sorting_type = "none";
                                for(var e in s.sorting) {
                                    if(s.sorting[e].field == s.columns[i].field) {
                                        sorting_type = s.sorting[e].order;
                                        break;
                                    }
                                }
                                switch(sorting_type) {
                                    case "ascending":
                                        sortingIndicator = '&nbsp;<span class="' + s.sortingIndicatorAscClass + '"></span>';
                                        break;
                                    case "descending":
                                        sortingIndicator = '&nbsp;<span class="' + s.sortingIndicatorDescClass + '"></span>';
                                        break;
                                    default:
                                        sortingIndicator = '';
                                }
                            }
                            tbl_html += '<th class="' + s.commonThClass + '">' + s.columns[i].header + sortingIndicator + '</th>';
                        }
                    }
                    tbl_html += '</tr>';
                    tbl_html += '</thead>';

                    tbl_html += '<tbody>';
                    for(row in page_data) {

                        row_id_html = (row_primary_key ? ' id="' + table_id + '_tr_' + page_data[row][row_primary_key] + '"' : '');
                        tbl_html += '<tr' + row_id_html + '>';

                        if(s.showRowNumbers) {
                            row_index = offset + parseInt(row) + 1;
                            tbl_html += '<td>' + row_index + '</td>';
                        }

                        for(i in s.columns) {
                            if(column_is_visible(s.columns[i])) {
                                tbl_html += '<td>' + page_data[row][s.columns[i].field] + '</td>';
                            }
                        }

                        tbl_html += '</tr>';
                    }
                    tbl_html += '<tbody>';

                    elem_table.html(tbl_html);

                    // refresh pagination (if needed)
                    if(refresh_pag) {
                        elem_pagination.bs_pagination({
                            currentPage: s.pageNum,
                            totalPages: Math.ceil(total_rows / s.rowsPerPage),
                            totalRows: total_rows
                        });
                    }

                    // no results
                    if(total_rows == 0) {
                        elem_pagination.hide();
                        elem_no_results.show();
                    } else {
                        elem_pagination.show();
                        elem_no_results.hide();
                    }

                    // apply given styles ------------------------------------------
                    var col_index = s.showRowNumbers ? 1 : 0,
                        headerClass = "", dataClass = "";
                    for(i in s.columns) {
                        if(column_is_visible(s.columns[i])) {
                            headerClass = "", dataClass = "";
                            if(columns[i].hasOwnProperty("headerClass")) {
                                headerClass = columns[i]["headerClass"];
                            }
                            if(columns[i].hasOwnProperty("dataClass")) {
                                dataClass = columns[i]["dataClass"];
                            }
                            methods.setPageColClass.call(elem, col_index, headerClass, dataClass);
                            col_index++;
                        }
                    }

                    // apply row selections ----------------------------------------
                    if(s.row_primary_key && s.selected_ids.length > 0) {

                        if(s.rowSelectionMode == "single" || s.rowSelectionMode == "multiple") {
                            var row_prefix_len = (table_id + "_tr_").length,
                                row_id, idx;
                            $("#" + table_id + " tbody tr").each(function() {
                                row_id = parseInt($(this).attr("id").substr(row_prefix_len));
                                idx = methods.selectedRows.call(elem, "selected_index", row_id);
                                if(idx > -1) {
                                    methods.selectedRows.call(elem, "mark_selected", row_id);
                                }
                            });
                        }
                    }

                    // update selected rows counter
                    methods.selectedRows.call(elem, "update_counter");

                    // trigger event onDisplay
                    elem.triggerHandler("onDisplay");

                }
            });

            return res;

        },

        /**
         * Get datagrid snapshot (current status: row selections, pagination, filters)
         * @returns {*}
         */
        takeSnapshot: function() {
            var elem = this;
            return $.extend(true, {}, methods.getAllOptions.call(elem));
        },

        /**
         * Restore taken snaphot
         * @param {obj} params
         */
        restoreSnapshot: function(params) {
            var elem = this;
            elem.removeData(pluginName);
            methods.init.call(elem, params);
        }

    };

    /* private methods ------------------------------------------------------ */

    /**
     * @lends _private_methods
     */

    /**
     * Create element id
     * @function
     * @param prefix
     * @param plugin_container_id
     * @return {*}
     */
    var create_id = function(prefix, plugin_container_id) {
        return prefix + plugin_container_id;
    };

    /**
     * Check if column is visible (utility function)
     *
     * @param {object} column
     * @returns {boolean}
     */
    var column_is_visible = function(column) {
        var visible = "visible";
        return !column.hasOwnProperty(visible) || (column.hasOwnProperty(visible) && column[visible] == "yes");
    };

    /**
     * Set column visible property (utility function)
     *
     * @param {object} column
     * @param {boolean} status
     */
    var set_column_visible = function(column, status) {
        var visible = "visible";
        if(status) {
            if(column.hasOwnProperty(visible)) {
                delete column[visible];
            }
        } else {
            column[visible] = "no";
        }
    };

    /**
     * Get column header (utility function)
     *
     * @param {object} column
     * @returns {string}
     */
    var get_column_header = function(column) {
        return column.hasOwnProperty("header") ? column["header"] : column["field"];
    };

    /**
     * Get sorting name (utility function)
     *
     * @param {object} sorting
     * @returns {string}
     */
    var get_sorting_name = function(sorting) {
        return sorting.hasOwnProperty("sortingName") ? sorting["sortingName"] : sorting["field"];
    };

    /**
     * Check if column is sortable (utility function)
     *
     * @param {object} column
     * @returns {boolean}
     */
    var column_is_sortable = function(column) {
        return !column.hasOwnProperty("sortable") || (column.hasOwnProperty("sortable") && column["sortable"] == "yes");
    };

    /**
     * Check if column is function (utility function)
     *
     * @param {object} column
     * @returns {boolean}
     */
    var column_is_function = function(column) {
        var is_function = "is_function";
        return column.hasOwnProperty(is_function) && column[is_function] == "yes";
    };

    /**
     * Move array element from fromIndex to toIndex
     * @param arr
     * @param fromIndex
     * @param toIndex
     */
    var array_move = function(arr, fromIndex, toIndex) {
        var element = arr[fromIndex];
        arr.splice(fromIndex, 1);
        arr.splice(toIndex, 0, element);
    };

    /**
     * bs_grid - datagrid jQuery plugin.
     *
     * @class bs_grid
     * @memberOf $.fn
     */
    $.fn.bs_grid = function(method) {

        if(this.size() != 1) {
            var err_msg = "You must use this plugin (" + pluginName + ") with a unique element (at once)";
            this.html('<span style="color: red;">' + 'ERROR: ' + err_msg + '</span>');
            $.error(err_msg);
        }

        // Method calling logic
        if(methods[method]) {
            return methods[ method ].apply(this, Array.prototype.slice.call(arguments, 1));
        } else if(typeof method === "object" || !method) {
            return methods.init.apply(this, arguments);
        } else {
            $.error("Method " + method + " does not exist on jQuery." + pluginName);
        }

    };

})(jQuery);