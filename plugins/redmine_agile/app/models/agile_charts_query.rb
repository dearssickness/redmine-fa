# This file is a part of Redmin Agile (redmine_agile) plugin,
# Agile board plugin for redmine
#
# Copyright (C) 2011-2020 RedmineUP
# http://www.redmineup.com/
#
# redmine_agile is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# redmine_agile is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with redmine_agile.  If not, see <http://www.gnu.org/licenses/>.

class AgileChartsQuery < AgileQuery
  unloadable

  validate :validate_query_dates

  attr_writer :date_from, :date_to

  def initialize(attributes = nil, *args)
    super attributes
    self.filters.delete('status_id')
    self.filters['chart_period'] = { operator: 'm', values: [''] } unless has_filter?('chart_period')
  end

  self.operators_by_filter_type[:chart_period] = ['><', 'w', 'lw', 'l2w', 'm', 'lm', 'y']

  def initialize_available_filters
    super

    add_available_filter 'chart_period', type: :date_past, name: l(:label_date)
  end

  def sprint_values
    AgileSprint.for_project(project).available.map { |s| [s.to_s, s.id.to_s] }
  end

  def default_columns_names
    @default_columns_names = [:id, :subject, :estimated_hours, :spent_hours, :done_ratio, :assigned_to]
  end

  def sql_for_chart_period_field(_field, _operator, _value)
    '1=1'
  end

  def chart
    @chart ||= RedmineAgile::Charts.valid_chart_name_by(options[:chart])
  end

  def chart=(arg)
    options[:chart] = arg
  end

  def date_from
    @date_from ||= chart_period[:from]
  end

  def date_to
    @date_to ||= chart_period[:to]
  end

  def interval_size
    if RedmineAgile::AgileChart::TIME_INTERVALS.include?(options[:interval_size])
      options[:interval_size]
    else
      RedmineAgile::AgileChart::DAY_INTERVAL
    end
  end

  def interval_size=(value)
    options[:interval_size] = value
  end

  def build_from_params(params)
    if params[:fields] || params[:f]
      self.filters = {}.merge(chart_period_filter(params))
      add_filters(params[:fields] || params[:f], params[:operators] || params[:op], params[:values] || params[:v])
    else
      available_filters.keys.each do |field|
        add_short_filter(field, params[field]) if params[field]
      end
    end
    self.group_by = params[:group_by] || (params[:query] && params[:query][:group_by])
    self.column_names = params[:c] || (params[:query] && params[:query][:column_names])
    self.date_from = params[:date_from] || (params[:query] && params[:query][:date_from])
    self.date_to = params[:date_to] || (params[:query] && params[:query][:date_to])
    self.chart = params[:chart] || (params[:query] && params[:query][:chart]) || params[:default_chart] || RedmineAgile.default_chart
    self.interval_size = params[:interval_size] || (params[:query] && params[:query][:interval_size]) || RedmineAgile::AgileChart::DAY_INTERVAL
    self.chart_unit = params[:chart_unit] || (params[:query] && params[:query][:chart_unit]) || RedmineAgile::Charts::UNIT_ISSUES

    self
  end

  def condition_for_status
    '1=1'
  end

  private

  def chart_period_filter(params)
    return {} if (params[:fields] || params[:f]).include?('chart_period')
    { 'chart_period' => { operator: 'm', values: [''] } }
  end

  def validate_query_dates
    if (self.date_from && self.date_to && self.date_from >= self.date_to)
      errors.add(:base, l(:label_agile_chart_dates) + ' ' + l(:invalid, scope: 'activerecord.errors.messages'))
    end
  end

  def db_timestamp_regex
    /(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:.\d*))/
  end

  def chart_period
    @chart_period ||= {
      from: chart_period_statement.match("chart_period > '#{db_timestamp_regex}") { |m| Time.zone.parse(m[1]) },
      to: chart_period_statement.match("chart_period <= '#{db_timestamp_regex}") { |m| Time.zone.parse(m[1]) }
    }
  end

  def chart_period_statement
    @chart_period_statement ||= build_chart_period_statement
  end

  def build_chart_period_statement
    field = 'chart_period'
    operator = filters[field][:operator]
    values = filters[field][:values]
    date = User.current.today

    case operator
    when 'w'
      first_day_of_week = (Setting.start_of_week || l(:general_first_day_of_week)).to_i
      day_of_week = date.cwday
      days_ago = (day_of_week >= first_day_of_week ? day_of_week - first_day_of_week : day_of_week + 7 - first_day_of_week)
      sql_for_field(field, '><t-', [days_ago], Issue.table_name, field)
    when 'm'
#      days_ago = date - date.beginning_of_month
      jdt_elements = jdate_elements()
      days_ago = date - jdt_elements["jtog_calendar_startdt"].to_date
      sql_for_field(field, '><t-', [days_ago], Issue.table_name, field)
    when 'y'
#      days_ago = date - date.beginning_of_year
      jdt_elements = jdate_elements()
      days_ago = date - jdt_elements["jtog_calendar_beginning_of_year"]
      sql_for_field(field, '><t-', [days_ago], Issue.table_name, field)
    when '><'
      sql_for_field(field, '><', present_values(values), Issue.table_name, field)
    else
      sql_for_field(field, operator, values, Issue.table_name, field)
    end
  end

  def present_values(values)
    return values unless values.is_a?(Array)

    from = Date.parse(values[0])
    to = Date.parse(values[1])
    [(from < Date.today ? from : Date.today).to_s, (Date.today < to ? Date.today : to).to_s]
  end

  def gregorian_to_jalali(date_time)
    unless date_time.nil?
      date_time = date_time.split()
      date_list = date_time[0].split('-')
      if date_list.length == 1 
        date_list = date_time[0].split('/')
      end
      if date_list[0] =~ /\d/
        date_list = date_list.map(&:to_i)
        gy = date_list[0]
        gm = date_list[1]
        gd = date_list[2]
    
        g_d_m = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        (gm > 2) ? gy2 = gy + 1 : gy2 = gy
        days = 355666 + (365 * gy) + Integer((gy2 + 3) / 4) - Integer((gy2 + 99) / 100) + Integer((gy2 + 399) / 400) + gd + g_d_m[gm - 1]
        jy = -1595 + (33 * Integer(days / 12053))
        days %= 12053
        jy += 4 * Integer(days / 1461)
        days %= 1461
        if days > 365
          jy += Integer((days - 1) / 365)
          days = (days - 1) % 365
        end
        if days < 186
          jm = 1 + Integer(days / 31)
          jd = 1 + (days % 31)
        else
          jm = 7 + Integer((days - 186) / 30)
          jd = 1 + ((days - 186) % 30)
        end
        converted_date = [jy, jm, jd]
        date_time[0] = converted_date.join('-')
        converted_datetime = date_time.join(' ').to_s
      else
        converted_datetime = date_time.join().to_s
      end
      converted_datetime
    end
  end

  def jalali_to_gregorian(date_time)
    date_time = date_time.split()
    date_list = date_time[0].split('-')
    if date_list.length == 1 
      date_list = date_time[0].split('/')
    end

    date_list = date_list.map(&:to_i)
    jy = date_list[0]
    jm = date_list[1]
    jd = date_list[2]

    jy += 1595
    days = -355668 + (365 * jy) + (Integer(jy / 33) * 8) + Integer(((jy % 33) + 3) / 4) + jd
    (jm < 7) ? days += (jm - 1) * 31 : days += ((jm - 7) * 30) + 186
    gy = 400 * Integer(days / 146097)
    days %= 146097
    if days > 36524
      days -= 1
      gy += 100 * Integer(days / 36524)
      days %= 36524
      days += 1 if days >= 365
    end
    gy += 4 * Integer(days / 1461)
    days %= 1461
    if days > 365
      gy += Integer((days - 1) / 365)
      days = (days - 1) % 365
    end
    gd = days + 1
    sal_a = [0, 31, ((gy % 4 == 0 and gy % 100 != 0) or (gy % 400 == 0)) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    gm = 0
    while gm < 13 and gd > sal_a[gm]
      gd -= sal_a[gm]
      gm += 1
    end
    converted_date = [gy, gm, gd]
    date_time[0] = converted_date.join('-')
    converted_datetime = date_time.join(' ').to_s
    converted_datetime
  end 

  def jdate_elements()
    jdate = gregorian_to_jalali(User.current.today.year.to_s+'-'+User.current.today.month.to_s+'-'+'13')
    jdt_elements = Hash.new
    jdate_list = jdate.split("-")
    jcurrent_month = jdate_list[1].to_i
    if jcurrent_month < 7
      jdt_elements["jnumber_of_days_in_month"] = 31
    elsif jcurrent_month < 12 && jcurrent_month > 6
      jdt_elements["jnumber_of_days_in_month"] = 30
    else
      jdt_elements["jnumber_of_days_in_month"] = 30
    end
    jcalendar_startdt = jdate_list[0]+'-'+jdate_list[1]+'-'+'1'
    jcalendar_enddt =  jdate_list[0]+'-'+jdate_list[1]+'-'+jdt_elements["jnumber_of_days_in_month"].to_s
    jdt_elements["jfirst_day_of_month_cwday"] = jalali_to_gregorian(jcalendar_startdt).to_date.cwday
    jdate_year_list = gregorian_to_jalali(User.current.today.year.to_s+'-'+'1'+'-'+'1').split('-')
    jdt_elements["jtog_calendar_beginning_of_year"] = jalali_to_gregorian(jdate_year_list[0].to_s+'-'+'1'+'-'+'1').to_date
    jdt_elements["jtog_calendar_startdt"] = jalali_to_gregorian(jcalendar_startdt).to_date
    jdt_elements["jtog_calendar_enddt"] = jalali_to_gregorian(jcalendar_enddt).to_date
    jdt_elements
  end
end
