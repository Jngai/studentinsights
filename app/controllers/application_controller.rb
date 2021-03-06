class ApplicationController < ActionController::Base

  rescue_from DeviseLdapAuthenticatable::LdapException do |exception|
    render text: exception, status: 500
  end

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
  unless Rails.env.development?
    force_ssl except: [:lets_encrypt_endpoint]
  end

  before_action :redirect_domain!
  before_action :authenticate_educator!  # Devise method, applies to all controllers.
                                         # In this app 'users' are 'educators'.

  # Return the homepage path, depending on the educator's role
  def homepage_path_for_role(educator)
    PathsForEducator.new(educator).homepage_path
  end

  # Wrap all database queries with this to enforce authorization
  def authorized(&block)
    authorizer.authorized(&block)
  end

  # Enforce authorization and raise if no authorized models
  def authorized_or_raise!(&block)
    return_value = authorizer.authorized(&block)
    if return_value == nil || return_value == []
      raise Exceptions::EducatorNotAuthorized
    end
    return_value
  end

  # Sugar for filters checking authorization
  def redirect_unauthorized!
    redirect_to not_authorized_path
  end

  def render_unauthorized_json!
    render json: { error: 'unauthorized' }, status: 403
  end

  # For redirecting requests directly from the Heroku domain to the canonical domain name
  def redirect_domain!
    canonical_domain = LoadDistrictConfig.new.canonical_domain
    return if canonical_domain == nil
    return if request.host == canonical_domain
    redirect_to "#{request.protocol}#{canonical_domain}#{request.fullpath}", :status => :moved_permanently
  end

  # Used to wrap a block with timing measurements and logging, returning the value of the
  # block.
  #
  # Example: students = log_timing('load students') { Student.all }
  # Outputs: log_timing:end [load students] 2998ms
  def log_timing(message)
    return_value = nil

    logger.info "log_timing:start [#{message}]"
    timing_ms = Benchmark.ms { return_value = yield }
    logger.info "log_timing:end [#{message}] #{timing_ms.round}ms"

    return_value
  end

  private
  def authorizer
    @authorizer ||= Authorizer.new(current_educator)
  end
end
