# This controller handles the login/logout function of the site.  
class SessionsController < ApplicationController
  # Be sure to include AuthenticationSystem in Application Controller instead
#  include AuthenticatedSystem
  permit 'not guest', :only => :destroy

  # render new.rhtml
  def new
  end
  
  def create
    user = User.authenticate(params[:login], params[:password])
    if user
      user.sessions.stale.destroy_all 
      if user.active?
        # Note: this is duplicated @ users_controller#rpx_login. Maybe refactorable, but not worth it.
        
        # Protects against session fixation attacks, causes request forgery
        # protection if user resubmits an earlier form using back button.
        logout_killing_session! # vs. logout_keeping_session
        self.current_user = user
        user.update_time_in_app!
        Event.event! current_user, 'log in'
        new_cookie_flag = (params[:remember_me] == "1")
        handle_remember_cookie! new_cookie_flag
        flash[:notice] = "Logged in successfully"
        redirect_back_or_default(@user)
      else
        flash[:error] = "Your account is #{user.state}. Please email an administrator to correct this."
        redirect_back_or_default('/')
      end
    else
      note_failed_signin
      @login       = params[:login]
      @remember_me = params[:remember_me]
      render :action => 'new'
    end
  end
  
  def destroy
    logout_killing_session!
    Event.event! current_user, 'log out'
    flash[:notice] = "You have been logged out."
    redirect_back_or_default('/')
  end

protected
  # Track failed login attempts
  def note_failed_signin
    flash[:error] = "Couldn't log you in as '#{params[:login]}'"
    logger.warn "Failed login for '#{params[:login]}' from #{request.remote_ip} at #{Time.now.utc}"
  end
end
