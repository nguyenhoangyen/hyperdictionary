class ApplicationController < ActionController::Base  
  # fixes 'can't dup NilClass' error introduced in rails 2.3.3 - see https://rails.lighthouseapp.com/projects/8994/tickets/2441-activerecordsessionstore-breaks-with-custom-model
  # this injects our custom Session class, which is used to catch multis & track IPs
  before_filter {|c| ActiveRecord::SessionStore.session_class = Session} 
  
  helper :all # include all helpers, all the time
  protect_from_forgery # See ActionController::RequestForgeryProtection for details
  
  include AuthenticatedSystem
  include ExceptionLoggable
  include Userstamp
  
  # Scrub sensitive or excessively large parameters from your log
  filter_parameter_logging :password, :password_confirmation, :old_password, :uploaded_data
  
  before_filter :local_cache_for_request # using cache_fu
  before_filter :set_cache_override # Be very careful using this on a high traffic page; all hits within the time of your hit will be uncached
  def set_cache_override
    returning true do
      ActsAsCached.skip_cache_gets = !!params[:skip_cache]
    end
  end
  
  
#  # Hack to show what requests a process is handling in top (if it's in short mode)
#  $PROC_NAME ||= "#{$0} #{$*.join(' ')}" # keep the original. Note that this isn't really what ps thinks it was to start; ruby's $0 isn't very smart, it seems
#  
#  before_filter :set_process_name_from_request
#  def set_process_name_from_request
#    $0 = request.path[0,16] + ' ' + $PROC_NAME
#  end
#  
#  after_filter :unset_process_name_from_request
#  def unset_process_name_from_request
#    $0 = request.path[0,15] + "* " + $PROC_NAME
#  end
  
  # This is a hack to get around cases (eg Flash) where we don't get the cookie per normal. 
  # Must be prepended to ensure it executes before anyone tries to access (and thus set) current_user
  # This is probably not the best way to do it, though; eg we ought to first check whether they log in from cookie, THEN try this
  prepend_before_filter :set_session_from_query
  def set_session_from_query
    # Refuse to set if we already have an active session
    self.session = Session.find_by_session_id(params[SESSION_KEY.to_sym]).data if params[SESSION_KEY.to_sym] and (session.nil? or session.empty?)
  end
  
  # Used to catch multis & record IPs
  # Maybe e.g. require extra auth if they're coming from a new IP, or use it for tracking suspicious behavior
  before_filter :inject_ip
  def inject_ip
    if logged_in?
      session[:last_user_id] ||= current_user.id
      session[:last_ip] ||= request.remote_ip
      if current_user.id != session[:last_user_id] 
        # Multi caught. Log it as a relationship; leave it passive.
        r = Relationship.find_or_initialize_by_from_user_id_and_to_user_id(session[:last_user_id], current_user.id)
        r.multi = true
        r.save
        rr = r.reciprocal
        rr.multi = true
        rr.save
        
        session[:last_user_id] = current_user.id
      end
      if request.remote_ip != session[:last_ip]
        logger.info "IP CHANGED: User #{current_user.login} from #{session[:first_ip]} and #{request.remote_ip}"
        session[:last_ip] = request.remote_ip
      end
    end
  end
end
