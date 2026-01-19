# =============================================================================
# ArgoCD Helm Values - Raspberry Pi Kubernetes Cluster用
# =============================================================================
# このファイルはRaspberry Pi環境に最適化されたArgoCD設定です。
# 必要に応じてカスタマイズしてください。
# =============================================================================

# -----------------------------------------------------------------------------
# グローバル設定
# -----------------------------------------------------------------------------
global:
  # Raspberry Pi (ARM64) 環境での動作を確認済みのイメージタグ
  # 最新バージョンは https://github.com/argoproj/argo-cd/releases で確認
  image:
    tag: "v3.2.5"

# -----------------------------------------------------------------------------
# Redis設定 (セッション管理・キャッシュ)
# -----------------------------------------------------------------------------
redis-ha:
  # Raspberry Piでは高可用性Redisは不要（リソース節約）
  enabled: false

redis:
  enabled: true
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi

# -----------------------------------------------------------------------------
# ArgoCD Server設定 (Web UI & API)
# -----------------------------------------------------------------------------
server:
  # レプリカ数（Raspberry Piでは1で十分）
  replicas: 1

  # リソース制限（Raspberry Pi向けに調整）
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi

  # サービス設定
  service:
    # NodePort: クラスタ外部からアクセス可能
    # LoadBalancer: MetalLB使用時に推奨
    # ClusterIP: Ingress使用時に推奨
    type: NodePort
    nodePortHttp: 30080
    nodePortHttps: 30443

  # Ingress設定（必要に応じて有効化）
  ingress:
    enabled: false
    # 有効にする場合は以下をカスタマイズ
    # ingressClassName: nginx
    # hosts:
    #   - argocd.local
    # tls:
    #   - secretName: argocd-tls
    #     hosts:
    #       - argocd.local

  # 追加の環境変数
  extraArgs:
    # HTTPSを無効化（開発環境用、本番では推奨しない）
    - --insecure

# -----------------------------------------------------------------------------
# ArgoCD Controller設定 (Git同期・リソース管理)
# -----------------------------------------------------------------------------
controller:
  replicas: 1

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 512Mi

  # 同期設定
  args:
    # アプリケーションのリソース数制限
    statusProcessors: "10"
    operationProcessors: "5"

# -----------------------------------------------------------------------------
# ArgoCD Repo Server設定 (Gitリポジトリ処理)
# -----------------------------------------------------------------------------
repoServer:
  replicas: 1

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 512Mi

  # Liveness probeのタイムアウトを延長（ARM64環境で安定性向上）
  livenessProbe:
    initialDelaySeconds: 30
    periodSeconds: 10
    timeoutSeconds: 10
    failureThreshold: 3

  readinessProbe:
    initialDelaySeconds: 10
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 3

# -----------------------------------------------------------------------------
# ArgoCD ApplicationSet Controller設定
# -----------------------------------------------------------------------------
applicationSet:
  enabled: true
  replicas: 1

  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi

# -----------------------------------------------------------------------------
# ArgoCD Notifications Controller設定
# -----------------------------------------------------------------------------
notifications:
  enabled: true

  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi

# -----------------------------------------------------------------------------
# Dex設定 (認証プロバイダー)
# -----------------------------------------------------------------------------
dex:
  # 外部認証を使わない場合は無効化してリソース節約
  enabled: false

# -----------------------------------------------------------------------------
# 設定管理
# -----------------------------------------------------------------------------
configs:
  # 管理者パスワード（設定しない場合は自動生成）
  # bcryptハッシュを使用: htpasswd -nbBC 10 "" your-password | tr -d ':\n' | sed 's/$2y/$2a/'
  # secret:
  #   argocdServerAdminPassword: ""

  # リポジトリ認証情報（プライベートリポジトリ用）
  repositories: {}
    # private-repo:
    #   url: https://github.com/your-org/private-repo.git
    #   password: your-token
    #   username: your-username

  # 既知のホスト鍵（SSH接続用）
  ssh:
    knownHosts: |
      github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
      gitlab.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCsj2bNKTBSpIYDEGk9KxsGh3mySTRgMtXL583qmBpzeQ+jqCMRgBqB98u3z++J1sKlXHWfM9dyhSevkMwSbhoR8XIq/U0tCNyokEi/ueaBMCvbcTHhO7FcwzY92WK4Zt0aGM5VE5/pN/zB2LoadCwEIB68ly+6PBpyQvA0anrU5FlBQEvgIfJHSxV0BAznE3M8FlBOaRRvsDvTzEYeqMFe0a8JKk4aDAN6ANnX0qsNH7GS8X9n0Wb7kR/l5QqXBn5NACi3ST/2I2bMMN5OlCdcPWoJ9znIrKMemBfrxS3LB0Wwxx9ivlBR/5B6BRlpyV/4sqQbIBgeNtWYjoj4P9s=

  # ConfigMap設定
  cm:
    # UIにクラスタ情報を表示
    statusbadge.enabled: "true"

    # ヘルスチェック設定
    resource.customizations: |
      networking.k8s.io/Ingress:
        health.lua: |
          hs = {}
          hs.status = "Healthy"
          return hs

  # パラメータ設定
  params:
    # サーバーサイドDiffを有効化（大規模リソース対応）
    server.enable.gzip: "true"
    # ログレベル
    server.log.level: "info"
