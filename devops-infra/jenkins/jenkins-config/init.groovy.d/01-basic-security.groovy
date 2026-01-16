#!groovy

import jenkins.model.*
import hudson.security.*
import jenkins.security.s2m.AdminWhitelistRule
import hudson.model.*

def instance = Jenkins.getInstance()

// Skip the setup wizard
instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)

// Create admin user
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "admin123")
instance.setSecurityRealm(hudsonRealm)

// Set authorization strategy - admin has all permissions
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

// Disable CLI over Remoting
instance.getDescriptor("jenkins.CLI").get().setEnabled(false)

// Enable Agent to Master Access Control
instance.getInjector().getInstance(AdminWhitelistRule.class).setMasterKillSwitch(false)

// Set admin email
instance.setSystemMessage("Jenkins configured automatically for AKS Data Structures DevOps")

// Save configuration
instance.save()

println "Basic security configuration completed"