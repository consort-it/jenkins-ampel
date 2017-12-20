#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'net/https'
require 'uri'
require 'optparse'
require 'active_support/inflector'
require 'dotenv/load'
require 'rest-client'

class Ampel

  JENKINS_JOBS_URI = URI("#{ENV['JENKINS_JOBS_URI']}/api/json?tree=jobs[name,lastCompletedBuild[number,result]]")
  JENKINS_USER = ENV['JENKINS_USER']
  JENKINS_PASS = ENV['JENKINS_PASS']
  SLACK_HOOK_URI = ENV['SLACK_HOOK_URI']

  def run(options)
    if ! is_jenkins_healthy?
      message = "ALERT: Jenkins is not responding! Red light is on. :-("

      toggle_green_light(false, options)
      toggle_red_light(true, options)
      send_slack_message(options, message)

      puts message
    elsif evaluate_jenkins_job_colors.size == 0
      message = "OK: Everything is fine again! Green light is on. :-)"

      toggle_green_light(true, options)
      toggle_red_light(false, options)
      send_slack_message(options, message)

      puts message
    else
      message = "ALERT: #{evaluate_jenkins_job_colors.size} failing jenkins #{cpluralize(evaluate_jenkins_job_colors.size, 'job')}! Red light is on. :-("

      toggle_green_light(false, options)
      toggle_red_light(true, options)
      send_slack_message(options, message)

      puts message
    end
  end

  def get_jenkins_response
    Net::HTTP.start(
      JENKINS_JOBS_URI.host,
      JENKINS_JOBS_URI.port,
      :use_ssl => JENKINS_JOBS_URI.scheme == 'https',
      :verify_mode => OpenSSL::SSL::VERIFY_NONE
    ) do |http|
      request = Net::HTTP::Get.new JENKINS_JOBS_URI.request_uri
      request.basic_auth JENKINS_USER, JENKINS_PASS

      return http.request(request)
    end
  end

  def is_jenkins_healthy?
    return true if get_jenkins_response.code.to_i == 200
  end

  def get_jenkins_json_jobs
    JSON.parse(get_jenkins_response.body)['jobs']
  end

  def evaluate_jenkins_job_colors
    red_jobs = []

    get_jenkins_json_jobs.each do |job|
      next unless job['lastCompletedBuild']

      # puts "#{job['name']} has status '#{job['lastCompletedBuild']['result']}'"

      red_jobs << job['name'] if job['lastCompletedBuild']['result'] == 'FAILURE'
    end

    return red_jobs
  end

  def toggle_green_light(status, options)
    case status
    when true
      switch = '-o'
    when false
      switch = '-f'
    else
      raise "toggle_green_light: I don't know what to do. Sorry!"
    end

    `sudo sispmctl #{switch} 1` unless options[:dry_run] == true
  end

  def toggle_red_light(status, options)
    case status
    when true
      switch = '-o'
    when false
      switch = '-f'
    else
      raise "toggle_red_light: I don't know what to do. Sorry!"
    end

    `sudo sispmctl #{switch} 2` unless options[:dry_run] == true
  end

  def toggle_siren(status, options)
    case status
    when true
      switch = '-o'
    when false
      switch = '-f'
    else
      raise "toggle_siren: I don't know what to do. Sorry!"
    end

    `sudo sispmctl #{switch} 3` unless options[:dry_run] == true
  end

  def cpluralize(number, text)
    return text.pluralize if number != 1
    return text.singularize if number == 1
  end

  def send_slack_message(options, message)
    if options[:slack] == true
      channel = "#ampel"
      slack_state_file = ".slack_state"

      if File.exists?(slack_state_file)
        unless File.read(slack_state_file) == message
          RestClient.post("#{SLACK_HOOK_URI}", {'channel' => channel, 'text' => message}.to_json, {content_type => :json, accept => :json})
        end
      end

      File.write(slack_state_file, message)
    end
  end

end
