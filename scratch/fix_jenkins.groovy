import jenkins.model.*
import hudson.model.*
import jenkins.security.*
import jenkins.security.apitoken.*

// 1. API Token 주입
def user = User.get('admin', false)
if (user != null) {
    def prop = user.getProperty(ApiTokenProperty.class)
    // 기존에 동일한 이름의 토큰이 있으면 제거하고 다시 생성
    prop.tokenStore.addFixedToken('GitopsWebhookToken2024', 'GitopsWebhookToken2024')
    user.save()
    println 'TOKEN_READY: GitopsWebhookToken2024'
}

// 2. CSRF 비활성화 (실시간)
Jenkins.instance.setCrumbIssuer(null)
Jenkins.instance.save()
println 'CSRF_DISABLED'

// 3. 권한 확인 (Anonymous Read/Build 허용)
def strategy = new hudson.security.GlobalMatrixAuthorizationStrategy()
strategy.add(Jenkins.READ, 'anonymous')
strategy.add(Item.READ, 'anonymous')
strategy.add(Item.BUILD, 'anonymous')
strategy.add(Item.DISCOVER, 'anonymous')
Jenkins.instance.setAuthorizationStrategy(strategy)
Jenkins.instance.save()
println 'PERMISSIONS_OPENED'
