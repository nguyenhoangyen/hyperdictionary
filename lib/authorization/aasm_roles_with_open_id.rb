module Authorization
  module AasmRolesWithOpenId
    unless Object.constants.include? "STATEFUL_ROLES_CONSTANTS_DEFINED"
      STATEFUL_ROLES_CONSTANTS_DEFINED = true # sorry for the C idiom
    end
  
    def self.included( recipient )
      recipient.extend( StatefulRolesClassMethods )
      recipient.class_eval do
        include StatefulRolesInstanceMethods
        include AASM
        aasm_column :state
        aasm_initial_state :initial => :pending
        aasm_state :passive
        aasm_state :active,  :enter => :do_activate
        aasm_state :suspended
        aasm_state :deleted, :enter => :do_delete
        
        aasm_event :activate do
          transitions :from => :passive, :to => :active # No registration step 
        end
        
        aasm_event :suspend do
          transitions :from => [:passive, :pending, :active], :to => :suspended
        end
        
        aasm_event :delete do
          transitions :from => [:passive, :pending, :active, :suspended], :to => :deleted
        end

        aasm_event :unsuspend do
          transitions :from => :suspended, :to => :active,  :guard => Proc.new {|u| !u.activated_at.blank? }
          transitions :from => :suspended, :to => :pending, :guard => Proc.new {|u| !u.activation_code.blank? }
          transitions :from => :suspended, :to => :passive
        end
      end
    end

    module StatefulRolesClassMethods
    end # class methods

    module StatefulRolesInstanceMethods
      # Returns true if the user has just been activated.
      def recently_activated?
        @activated
      end
      
      def forgot_password!
        @forgotten_password = true
        self.password_reset_code = self.class.make_token
      end
      
      def recently_forgot_password?
        @forgotten_password
      end
      
      def reset_password!
        @reset_password = true
        self.password_reset_code = nil
      end
      
      def recently_reset_password?
        @reset_password
      end
      
      def do_delete
        self.deleted_at = Time.now.utc
      end
      
      def do_activate
        @activated = true
        self.deleted_at = nil
      end
    end # instance methods
  end
end
