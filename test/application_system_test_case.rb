require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  if ENV['HEADLESS']
    puts 'System tests running in headless mode...'
    driven_by :selenium, using: :chrome, screen_size: [1400, 1400], options: {
        desired_capabilities: {
            chromeOptions: {
                args: %w[headless disable-gpu no-sandbox]
            },
        },
    }
  else
    driven_by :selenium, using: :chrome, screen_size: [1400, 1400]
  end
end
