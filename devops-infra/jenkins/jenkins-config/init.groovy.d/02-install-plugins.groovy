#!groovy

import jenkins.model.*
import hudson.model.*
import hudson.PluginWrapper
import hudson.PluginManager

def instance = Jenkins.getInstance()
def pm = instance.getPluginManager()
def uc = instance.getUpdateCenter()

// List of required plugins
def plugins = [
    'workflow-aggregator',
    'pipeline-stage-view', 
    'pipeline-graph-view',
    'git',
    'github',
    'github-branch-source',
    'github-pullrequest',
    'ssh-agent',
    'credentials',
    'credentials-binding',
    'ssh-credentials',
    'docker-workflow',
    'docker-plugin',
    'kubernetes',
    'kubernetes-cli',
    'kubernetes-credentials-provider',
    'gradle',
    'nodejs',
    'junit',
    'cobertura',
    'htmlpublisher',
    'slack',
    'email-ext',
    'timestamper',
    'ansicolor',
    'rebuild',
    'build-timeout',
    'ws-cleanup',
    'role-strategy',
    'configuration-as-code',
    'job-dsl'
]

def installed = false
def initialized = false

def installPlugin(String name) {
    if (!pm.getPlugin(name)) {
        def plugin = uc.getPlugin(name)
        if (plugin) {
            println "Installing plugin: ${name}"
            plugin.deploy()
            installed = true
        } else {
            println "Plugin not found in update center: ${name}"
        }
    } else {
        println "Plugin already installed: ${name}"
    }
}

// Force update center refresh if not initialized
if (!uc.getSites().isEmpty() && !initialized) {
    println "Updating plugin update center..."
    uc.updateAllSites()
    initialized = true
    // Wait a bit for update center to refresh
    Thread.sleep(5000)
}

// Install each plugin
plugins.each { plugin ->
    installPlugin(plugin)
}

if (installed) {
    println "Plugins installed. Jenkins restart required."
    // Don't restart automatically to avoid issues during provisioning
} else {
    println "No new plugins to install."
}

instance.save()