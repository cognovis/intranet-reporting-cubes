# /packages/intranet-reporting-cubes/www/finance-cube.tcl
#
# Copyright (c) 2003-2013 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/ for licensing details.

ad_page_contract {
    Cost Cube
} {
    { start_date "2000-01-01" }
    { end_date "2099-12-31" }
    { top_var1 "year quarter_of_year" }
    { top_var2 "" }
    { top_var3 "" }
    { left_var1 "customer_name" }
    { left_var2 "" }
    { left_var3 "" }
    { cost_type_id:multiple "3700" }
    { customer_type_id:integer 0 }
    { customer_id:integer 0 }
    { output_format "html" }

    { left_vars "" }
    { top_vars "" }
}

# ------------------------------------------------------------
# Define Dimensions

# Left Dimension - defined by users selects
set left {}
if {"" != $left_vars} {
    # override left vars with elements from list
    set left_var1 [lindex $left_vars 0]
    set left_var2 [lindex $left_vars 1]
    set left_var3 [lindex $left_vars 2]
}
if {"" != $left_var1} { lappend left $left_var1 }
if {"" != $left_var2} { lappend left $left_var2 }
if {"" != $left_var3} { lappend left $left_var3 }


# Top Dimension
set top_var1 [ns_urldecode $top_var1]


if {"" != $top_vars} {
    # override top vars with elements from list
    # Special logic for top_var1 for date dimension - very ugly...
    set top_var1 [lindex $top_vars 0]

    if {[lrange $top_vars 0 3] == {year quarter_of_year month_of_year day_of_month}} {
	set top_var1 [lrange $top_vars 0 3]
	set top_vars [lrange $top_vars 3 end]
    }
    if {[lrange $top_vars 0 2] == {year quarter_of_year month_of_year}} {
	set top_var1 [lrange $top_vars 0 2]
	set top_vars [lrange $top_vars 2 end]
    }
    if {[lrange $top_vars 0 1] == {year quarter_of_year}} {
	set top_var1 [lrange $top_vars 0 1]
	set top_vars [lrange $top_vars 1 end]
    }
    if {[lrange $top_vars 0 1] == {year month_of_year}} {
	set top_var1 [lrange $top_vars 0 1]
	set top_vars [lrange $top_vars 1 end]
    }
    if {[lrange $top_vars 0 1] == {year week_of_year}} {
	set top_var1 [lrange $top_vars 0 1]
	set top_vars [lrange $top_vars 1 end]
    }
    if {[lrange $top_vars 0 1] == {quarter_of_year year}} {
	set top_var1 [lrange $top_vars 0 1]
	set top_vars [lrange $top_vars 1 end]
    }
    if {[lrange $top_vars 0 1] == {month_of_year year}} {
	set top_var1 [lrange $top_vars 0 1]
	set top_vars [lrange $top_vars 1 end]
    }

    set top_var2 [lindex $top_vars 1]
    set top_var3 [lindex $top_vars 2]
}


set top {}
if {"" != $top_var1} { lappend top $top_var1 }
if {"" != $top_var2} { lappend top $top_var2 }
if {"" != $top_var3} { lappend top $top_var3 }

# Flatten lists - kinda dirty...
regsub -all {[\{\}]} $top "" top
regsub -all {[\{\}]} $left "" left


# The complete set of dimensions - used as the key for
# the "cell" hash. Subtotals are calculated by dropping on
# or more of these dimensions
set dimension_vars [concat $top $left]

# Check for duplicate variables
set unique_dimension_vars [lsort -unique $dimension_vars]
if {[llength $dimension_vars] != [llength $unique_dimension_vars]} {
    ad_return_complaint 1 "<b>Duplicate Variable</b>:<br>
    You have specified a variable more then once."
}

# ------------------------------------------------------------
# Security

# Label: Provides the security context for this report
# because it identifies unquely the report's Menu and
# its permissions.
set menu_label "reporting-cubes-finance"
set current_user_id [ad_maybe_redirect_for_registration]
set read_p [db_string report_perms "
	select	im_object_permission_p(m.menu_id, :current_user_id, 'read')
	from	im_menus m
	where	m.label = :menu_label
" -default 'f']

if {![string equal "t" $read_p]} {
    ad_return_complaint 1 "<li>
[lang::message::lookup "" intranet-reporting.You_dont_have_permissions "You don't have the necessary permissions to view this page"]"
    return
}


# ------------------------------------------------------------
# Check Parameters

# Check that Start & End-Date have correct format
if {"" != $start_date && ![regexp {^[0-9][0-9][0-9][0-9]\-[0-9][0-9]\-[0-9][0-9]$} $start_date]} {
    ad_return_complaint 1 "Start Date doesn't have the right format.<br>
    Current value: '$start_date'<br>
    Expected format: 'YYYY-MM-DD'"
}

if {"" != $end_date && ![regexp {^[0-9][0-9][0-9][0-9]\-[0-9][0-9]\-[0-9][0-9]$} $end_date]} {
    ad_return_complaint 1 "End Date doesn't have the right format.<br>
    Current value: '$end_date'<br>
    Expected format: 'YYYY-MM-DD'"
}


# ------------------------------------------------------------
# Deal with invoices related to multiple projects
im_invoices_check_for_multi_project_invoices

# ------------------------------------------------------------
# Page Title & Help Text

set cost_type [db_list cost_type "
	select	im_category_from_id(category_id)
	from	im_categories
	where	category_id in ([join $cost_type_id ", "])
"]

set page_title [lang::message::lookup "" intranet-reporting.Financial_Cube "Financial Cube"]
set context_bar [im_context_bar $page_title]
set context ""
set help_text "<strong>$page_title</strong><br>

This Pivot Table ('cube') is a kind of report that shows Invoice,
Quote or Delivery Note amounts according to a a number of variables
that you can specify.
This cube effectively replaces a dozen of specific reports and allows
you to 'drill down' into results.
<p>

Please Note: Financial documents associated with multiple projects
are not included in this overview.
"


# ------------------------------------------------------------
# Defaults

set rowclass(0) "roweven"
set rowclass(1) "rowodd"

set gray "gray"

set days_in_past 365

set derefs [list]

set default_currency [ad_parameter -package_id [im_package_cost_id] "DefaultCurrency" "" "EUR"]
set cur_format [im_l10n_sql_currency_format]
set date_format [im_l10n_sql_date_format]

db_1row todays_date "
select
	to_char(sysdate::date - :days_in_past::integer, 'YYYY') as todays_year,
	to_char(sysdate::date - :days_in_past::integer, 'MM') as todays_month,
	to_char(sysdate::date - :days_in_past::integer, 'DD') as todays_day
from dual
"

if {"" == $start_date} { 
    set start_date "$todays_year-$todays_month-01"
}

db_1row end_date "
select
	to_char(to_date(:start_date, 'YYYY-MM-DD') + :days_in_past::integer, 'YYYY') as end_year,
	to_char(to_date(:start_date, 'YYYY-MM-DD') + :days_in_past::integer, 'MM') as end_month,
	to_char(to_date(:start_date, 'YYYY-MM-DD') + :days_in_past::integer, 'DD') as end_day
from dual
"

if {"" == $end_date} { 
    set end_date "$end_year-$end_month-01"
}


set company_url "/intranet/companies/view?company_id="
set project_url "/intranet/projects/view?project_id="
set invoice_url "/intranet-invoices/view?invoice_id="
set user_url "/intranet/users/view?user_id="
set this_url [export_vars -base "/intranet-reporting/finance-cube" {start_date end_date} ]


# ------------------------------------------------------------
# Options

set cost_type_options {
	3700 "Customer Invoice"
	3702 "Quote"
	3724 "Delivery Note"

	3704 "Provider Bill"
	3706 "Purchase Order"
	3734 "Provider Receipt"

	3722 "Expense Report"
	3720 "Expense Item"
	3728 "Expense Planned Cost"	

	3718 "Timesheet Cost"
	3726 "Timesheet Budget"

}

set non_active_cost_type_options {
	3714 "Employee Salary"
        3716 "Repeating Cost"
	3730 "InterCo Invoice"
	3732 "InterCo Quote"
	3736 "Timesheet Hours"
}

set top_vars_options {
	"" "No Date Dimension" 
	"year" "Year" 
	"year quarter_of_year" "Year and Quarter" 
	"year month_of_year" "Year and Month" 
	"year quarter_of_year month_of_year" "Year, Quarter and Month" 
	"year quarter_of_year month_of_year day_of_month" "Year, Quarter, Month and Day" 
	"year week_of_year" "Year and Week"
	"quarter_of_year year" "Quarter and Year (compare quarters)"
	"month_of_year year" "Month and Year (compare months)"
}

set left_scale_options {
	"" ""

	"customer_name" "Customer Name"
	"customer_path" "Customer Nr"
	"customer_type" "Customer Type"
	"customer_status" "Customer Status"

	"provider_name" "Provider Name"
	"provider_path" "Provider Nr"
	"provider_type" "Provider Type"
	"provider_status" "Provider Status"

	"creation_user_name" "Creation User Name"
	"creation_user_cost_center_name" "Creation User Department"

	"mainp_project_name" "Main Project Name"
	"mainp_project_nr" "Main Project Nr"
	"subp_project_name" "Leaf Project Name"
	"subp_project_nr" "Leaf Project Nr"

	"cost_type" "Cost Type"
	"cost_status" "Cost Status"
	"cost_center" "Cost Center"
        "currency" "Cost Currency"
        "customer_contact_name" "Customer Contact"
        "customer_payment_method" "Customer Payment Method"
}

# ------------------------------------------------------------
# Add project options
lappend derefs "mainp.project_name as mainp_project_name"
lappend derefs "mainp.project_nr as mainp_project_nr"
lappend derefs "subp.project_name as subp_project_name"
lappend derefs "subp.project_nr as subp_project_nr"

# ------------------------------------------------------------
# add all DynField attributes from Projects with datatype integer and a
# CategoryWidget for display. This widget shows distinct values suitable
# as dimension.

# ----------------------------------------------------------------
# Companies (both Customer and Provider)
#
set company_dynfield_sql "
	select	aa.attribute_name,
		aa.pretty_name,
		w.widget as tcl_widget,
		w.widget_name as dynfield_widget,
		w.deref_plpgsql_function
	from
		im_dynfield_attributes a,
		im_dynfield_widgets w,
		acs_attributes aa
	where
		a.widget_name = w.widget_name
		and a.acs_attribute_id = aa.attribute_id
		and w.widget in ('select', 'generic_sql', 'im_category_tree', 'im_cost_center_tree', 'checkbox')
		and aa.object_type in ('im_company')
		and aa.attribute_name not like 'default%'
" 

db_foreach company_dynfield_attributes $company_dynfield_sql {

    lappend left_scale_options "cust_${attribute_name}_deref"
    lappend left_scale_options "Customer $pretty_name"
    lappend left_scale_options "prov_${attribute_name}_deref"
    lappend left_scale_options "Provider $pretty_name"

    # Skip adding "deref" stuff if the variable is not looked at...
    if {[lsearch $dimension_vars "cust_${attribute_name}_deref"] + [lsearch $dimension_vars "prov_${attribute_name}_deref"] < 0} { 
	continue 
    }

    # Catch the generic ones - We know how to dereferentiate integer references of these fields.
    if {"" != $deref_plpgsql_function} {
	lappend derefs "${deref_plpgsql_function} (cust.$attribute_name) as cust_${attribute_name}_deref"
	lappend derefs "${deref_plpgsql_function} (prov.$attribute_name) as prov_${attribute_name}_deref"
    } else {
	lappend derefs "cust.$attribute_name as cust_${attribute_name}_deref"
	lappend derefs "prov.$attribute_name as prov_${attribute_name}_deref"
    }
}


# ----------------------------------------------------------------
# Main- and Leaf Projects
#
set project_dynfield_sql "
	select	aa.attribute_name,
		aa.pretty_name,
		w.widget as tcl_widget,
		w.widget_name as dynfield_widget,
		w.deref_plpgsql_function
	from
		im_dynfield_attributes a,
		im_dynfield_widgets w,
		acs_attributes aa
	where
		a.widget_name = w.widget_name
		and a.acs_attribute_id = aa.attribute_id
		and w.widget in ('select', 'generic_sql', 'im_category_tree', 'im_cost_center_tree', 'checkbox')
		and aa.object_type in ('im_project')
		and aa.attribute_name not like 'default%'
" 
db_foreach project_dynfield_attributes $project_dynfield_sql {

    lappend left_scale_options "mainp_${attribute_name}_deref"
    lappend left_scale_options "Main Project $pretty_name"

    lappend left_scale_options "subp_${attribute_name}_deref"
    lappend left_scale_options "Leaf Project $pretty_name"

    # Skip adding "deref" stuff if the variable is not looked at...
    if {[lsearch $dimension_vars "mainp_${attribute_name}_deref"] < 0 && [lsearch $dimension_vars "subp_${attribute_name}_deref"] < 0} { 
	continue 
    }

    # Catch the generic ones - We know how to dereferentiate integer references of these fields.
    if {"" != $deref_plpgsql_function} {
	lappend derefs "${deref_plpgsql_function} (mainp.$attribute_name) as mainp_${attribute_name}_deref"
	lappend derefs "${deref_plpgsql_function} (subp.$attribute_name) as subp_${attribute_name}_deref"
    } else {
	lappend derefs "mainp.$attribute_name as mainp_${attribute_name}_deref"
	lappend derefs "subp.$attribute_name as subp_${attribute_name}_deref"
    }
}

# ad_return_complaint 1 "<pre>[join $derefs "\n"]</pre>"


# ----------------------------------------------------------------
# Creation User
#
set dynfield_sql "
	select	aa.attribute_name,
		aa.pretty_name,
		aa.object_type,
		aa.table_name,
		w.widget as tcl_widget,
		w.widget_name as dynfield_widget,
		w.deref_plpgsql_function
	from
		im_dynfield_attributes a,
		im_dynfield_widgets w,
		acs_attributes aa
	where
		a.widget_name = w.widget_name
		and a.acs_attribute_id = aa.attribute_id
		and w.widget in ('select', 'generic_sql', 'im_category_tree', 'im_cost_center_tree', 'checkbox')
		and aa.object_type in ('person')
"

db_foreach dynfield_attributes $dynfield_sql {
    lappend left_scale_options "${attribute_name}_deref"
    lappend left_scale_options "Creation User $pretty_name"

    # Skip adding "deref" stuff if the variable is not looked at...
    if {[lsearch $dimension_vars ${attribute_name}_deref] < 0} { 
	continue 
    }

    switch $table_name {
	im_employees { set table_prefix "e" }
	users { set table_prefix "u" }
	parties { set table_prefix "pa" }
	default { set table_prefix "pe" }
    }

    # Catch the generic ones - We know how to dereferentiate integer references of these fields.
    set deref "${deref_plpgsql_function}($table_prefix.$attribute_name) as ${attribute_name}_deref"
    lappend derefs $deref
}


# ----------------------------------------------------------------
# Sort the left_scale_options
#

set left_scale_options [im_reporting_cube_sort_options $left_scale_options]
if {[llength $derefs] == 0} { lappend derefs "1 as dummy"}


for {set i 0} {$i < [llength $left_scale_options]} {incr i 2} {
    set deref [lindex $left_scale_options $i]
    set name  [lindex $left_scale_options [expr $i+1]]
    set left_scale_options_hash($name) $deref
}

set sorted_left_scale_options [list]
foreach name [lsort [array names left_scale_options_hash]] {
    set deref $left_scale_options_hash($name)
    lappend sorted_left_scale_options $deref
    lappend sorted_left_scale_options $name
}

set left_scale_options $sorted_left_scale_options


# ------------------------------------------------------------
# Start formatting the page
#

# Write out HTTP header, considering CSV/MS-Excel formatting
im_report_write_http_headers -output_format $output_format -report_name "finance-cube"

switch $output_format {
    html {
	ns_write "
		 [im_header]
		 [im_navbar]
	 	 <form>
		 <table cellspacing=0 cellpadding=0 border=0>
			[export_form_vars project_id]
			<tr valign=top><td>
			    	<table border=0 cellspacing=1 cellpadding=1>
				<tr>
					<td class=form-label>Start Date</td>
					<td class=form-widget colspan=3>
					<input type=textfield name=start_date value=$start_date>
					</td>
				</tr>
				<tr>
					<td class=form-label>End Date</td>
					<td class=form-widget colspan=3>
					    <input type=textfield name=end_date value=$end_date>
					</td>
				</tr>
				<tr>
					<td class=form-label>Cost Type</td>
					<td class=form-widget colspan=3>
					    [im_select -translate_p 1 -multiple_p 1 -size 7 cost_type_id $cost_type_options $cost_type_id]
					</td>
				</tr>
				<tr>
					<td class=form-label>Customer Type</td>
					<td class=form-widget colspan=3>
					    [im_category_select -include_empty_p 1 "Intranet Company Type" customer_type_id $customer_type_id]
					</td>
				</tr>
				<tr>
					<td class=form-label>Customer</td>
					<td class=form-widget colspan=3>
					    [im_company_select customer_id $customer_id]
					</td>
				</tr>
				<tr>
					<td class=form-widget colspan=2 align=center>Left-Dimension</td>
					<td class=form-widget colspan=2 align=center>Top-Dimension</td>
				</tr>
				<tr>
					<td class=form-label>Left 1</td>
					<td class=form-widget>
					    [im_select -translate_p 0 left_var1 $left_scale_options $left_var1]
					</td>

					<td class=form-label>Date Dimension</td>
					<td class=form-widget>
					    [im_select -translate_p 0 top_var1 $top_vars_options $top_var1]
					</td>
				</tr>
				<tr>
					<td class=form-label>Left 2</td>
					<td class=form-widget>
					    [im_select -translate_p 0 left_var2 $left_scale_options $left_var2]
					</td>
					<td class=form-label>Top 1</td>
					<td class=form-widget>
					    [im_select -translate_p 0 top_var2 $left_scale_options $top_var2]
					</td>
				</tr>
				<tr>
					<td class=form-label>Left 3</td>
					<td class=form-widget>
					    [im_select -translate_p 0 left_var3 $left_scale_options $left_var3]
					</td>
					<td class=form-label>Top 2</td>
					<td class=form-widget>
					    [im_select -translate_p 0 top_var3 $left_scale_options $top_var3]
					</td>
				</tr>
                                <tr>
                                          <td class=form-label> [lang::message::lookup "" intranet-reporting.Format "Format"]</td>
                                          <td class=form-widget>
                                                [im_report_output_format_select output_format "" $output_format]
                                          </td>
                                </tr>

				<tr>
					<td class=form-label></td>
					<td class=form-widget colspan=3><input type=submit value=Submit></td>
				</tr>
				</table>
			</td>
			<td></td>
			<td>
				<table cellspacing=2 width=90%>
					<tr><td>$help_text</td></tr>
				</table>
			</td>
		</tr>
		</table>
		</form>
		"
     }
}

# ------------------------------------------------------------
# Get the cube data
#

set cube_array [im_reporting_cubes_cube \
    -output_format $output_format \
    -cube_name "finance" \
    -start_date $start_date \
    -end_date $end_date \
    -left_vars $left \
    -top_vars $top \
    -cost_type_id $cost_type_id \
    -customer_type_id $customer_type_id \
    -customer_id $customer_id \
    -derefs $derefs \
    -no_cache_p 1 \
]


if {"" != $cube_array} {
    array set cube $cube_array

    # Extract the variables from cube
    set left_scale $cube(left_scale)
    set top_scale $cube(top_scale)
    array set hash $cube(hash_array)

    # ------------------------------------------------------------
    # Display the Cube Table

    ns_write [im_reporting_cubes_display \
	      -output_format $output_format \
	      -hash_array [array get hash] \
	      -left_vars $left \
	      -top_vars $top \
	      -top_scale $top_scale \
	      -left_scale $left_scale \
    ]
}

# ------------------------------------------------------------
# Finish up the table

if { "html" == $output_format } {
    ns_write "[im_footer]\n"
}


