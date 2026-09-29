[CmdletBinding()]
param(
    [switch]$Instantiation
)

# 宿主模块仓的只读项目合同检查（随 0000-002-ModuleReady 模板派生，派生后不必改本文件）。
#
# 模块身份不写死：从 b-Code/*/module.manifest.json 里找唯一的模块，其余名字全部由它推出。
# 检查的都是「宿主或 Aurora 那边只会静默失败」的事：版本三处一致、模块身份、页面 owner 与指令域、
# z-Publish 按字节入库；外加目录级别、失效链接、密钥与占位符。
#
# 本脚本只读，不提交、不推送、不发布、不改外部系统。

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$errors = [Collections.Generic.List[string]]::new()
$warnings = [Collections.Generic.List[string]]::new()
$generated = '\\(?:bin|obj|\.git|z-Publish)\\'

function Require-File([string]$RelativePath) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $RelativePath) -PathType Leaf)) {
        $errors.Add("缺少必需文件: $RelativePath")
    }
}

function Require-Directory([string]$RelativePath) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $RelativePath) -PathType Container)) {
        $errors.Add("缺少必需目录: $RelativePath")
    }
}

function Read-Text([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

try {
    $manifest = Read-Text (Join-Path $repoRoot 'project.manifest.json') | ConvertFrom-Json
}
catch {
    throw "无法读取 project.manifest.json: $($_.Exception.Message)"
}
$isTemplate = [bool]$manifest.template.isTemplate

foreach ($field in @('id', 'name', 'title', 'status', 'version')) {
    if ([string]::IsNullOrWhiteSpace([string]$manifest.project.$field)) {
        $errors.Add("project.manifest.json 缺少 project.$field")
    }
}

Require-File 'README.md'
Require-File 'AGENTS.md'
Require-File 'Logo.png'
Require-File 'Directory.Build.props'
foreach ($property in $manifest.documents.PSObject.Properties) {
    Require-File $property.Value
}
foreach ($directory in @($manifest.paths.activeRoots)) {
    Require-Directory $directory
}

# 根目录可见文件夹只允许 a-/b-/z- 三个级别。
$allowedPrefixes = @($manifest.paths.allowedRootDirectoryPrefixes)
Get-ChildItem -LiteralPath $repoRoot -Directory |
    Where-Object { -not $_.Name.StartsWith('.') } |
    ForEach-Object {
        $name = $_.Name
        if (-not ($allowedPrefixes | Where-Object { $name.StartsWith($_) })) {
            $errors.Add("根目录出现无级别文件夹: $name")
        }
    }

# ---- 找模块：b-Code 下唯一一份 module.manifest.json ----
$moduleManifests = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'b-Code') -Recurse -File -Filter 'module.manifest.json' |
    Where-Object { $_.FullName -notmatch $generated })
if ($moduleManifests.Count -ne 1) {
    $errors.Add("b-Code 下必须恰好有一份 module.manifest.json，实际 $($moduleManifests.Count) 份")
    $errors | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

$componentRoot = $moduleManifests[0].DirectoryName
$moduleManifest = Read-Text $moduleManifests[0].FullName | ConvertFrom-Json
$moduleName = [string]$moduleManifest.name
if ($moduleName -cnotmatch '^History[A-Z][A-Za-z0-9]*$') {
    $errors.Add("模块名必须形如 History<神名>，实际 $moduleName")
}
if ((Split-Path -Leaf $componentRoot) -ne $moduleName) {
    $errors.Add("模块目录名必须与模块名相同：b-Code/$moduleName/")
}
if ($moduleManifest.type -ne 'HistoryVulcan.Module') {
    $errors.Add('module.manifest.json 的 type 必须是 HistoryVulcan.Module')
}
if ($moduleManifest.artifact -ne "$moduleName.dll") {
    $errors.Add("module.manifest.json 的 artifact 必须是 $moduleName.dll")
}
if (-not $isTemplate -and $manifest.project.name -ne $moduleName) {
    $errors.Add("project.name 必须等于模块名 $moduleName")
}

# 版本三处一致。宿主对版本漂移的处理是静默跳过整个模块，只在日志留一行警告，
# 所以这条必须是构建前的硬失败，而不是发布后的现场排查。
$propsPath = Join-Path $componentRoot "${moduleName}Version.props"
$moduleVersion = $null
if (-not (Test-Path -LiteralPath $propsPath)) {
    $errors.Add("缺少版本真源 ${moduleName}Version.props")
}
else {
    $versionMatch = [regex]::Match((Read-Text $propsPath), "<${moduleName}Version>(?<v>[^<]+)</${moduleName}Version>")
    if (-not $versionMatch.Success) {
        $errors.Add("${moduleName}Version.props 必须声明 <${moduleName}Version>")
    }
    else {
        $moduleVersion = $versionMatch.Groups['v'].Value
        if ($manifest.project.version -ne $moduleVersion -or $moduleManifest.version -ne $moduleVersion) {
            $errors.Add("版本必须三处一致：project.manifest=$($manifest.project.version) props=$moduleVersion module.manifest=$($moduleManifest.version)")
        }
    }
}

$moduleInfoPath = Join-Path $componentRoot 'ModuleInfo.cs'
if (-not (Test-Path -LiteralPath $moduleInfoPath) -or
    (Read-Text $moduleInfoPath) -notmatch "ModuleName\s*=>\s*`"$moduleName`"") {
    $errors.Add("ModuleInfo.ModuleName 必须显式返回 $moduleName：缺省值是程序集名，同时也是指令域")
}

# 页面 owner 必须等于 "History" + 首字母大写的指令域。Aurora 对不上时整页静默拒收，
# 只在日志留一条 Warn——界面上表现为「模块装上了但页面不见了」。
$identityFiles = @(Get-ChildItem -LiteralPath $componentRoot -File -Filter '*Identity.cs')
if ($identityFiles.Count -ne 1) {
    $errors.Add('模块目录下必须恰好有一个 *Identity.cs（模块名、指令域与页面身份的唯一权威源）')
}
else {
    $identitySource = Read-Text $identityFiles[0].FullName
    $domainMatch = [regex]::Match($identitySource, 'Domain\s*=\s*"(?<d>[a-z][a-z0-9]*)"')
    $ownerMatch = [regex]::Match($identitySource, 'PageOwner\s*=\s*"(?<o>[^"]+)"')
    if (-not $domainMatch.Success -or -not $ownerMatch.Success) {
        $errors.Add("$($identityFiles[0].Name) 必须声明 Domain（小写字母数字）与 PageOwner 字面量")
    }
    else {
        $domain = $domainMatch.Groups['d'].Value
        $expectedOwner = 'History' + $domain.Substring(0, 1).ToUpperInvariant() + $domain.Substring(1)
        if ($ownerMatch.Groups['o'].Value -cne $expectedOwner) {
            $errors.Add("页面 owner 必须是 $expectedOwner（由指令域 $domain 推出），实际 $($ownerMatch.Groups['o'].Value)")
        }
    }
}

$sourceFiles = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'b-Code') -Recurse -File -Filter '*.cs' |
    Where-Object { $_.FullName -notmatch $generated }
foreach ($source in $sourceFiles) {
    $content = Read-Text $source.FullName
    if ($content -match 'context\.Settings|context\.DataDirectory') {
        $errors.Add("模块不得读取已移除的 IModuleContext 成员: $($source.FullName)")
    }
    # 宿主用可卸载装载上下文装模块，其中的类型不能参与 COM 互操作。
    if ($content -match '\[ComImport') {
        $errors.Add("模块内不得定义 [ComImport] 类型（可卸载装载上下文不支持）；Interop 请装进 AssemblyLoadContext.Default: $($source.FullName)")
    }
}

foreach ($projectFile in Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.csproj' |
    Where-Object { $_.FullName -notmatch $generated }) {
    $content = Read-Text $projectFile.FullName
    if ($content -match '<ProjectReference[^>]+(?:\.\.\\|\.\./)+\d{4}-') {
        $errors.Add("不得跨仓 ProjectReference: $($projectFile.FullName)")
    }
}

# 发布快照按字节入库。缺这条时 finish 热装会因 SHA256SUMS 不符失败。
if ((Read-Text (Join-Path $repoRoot '.gitattributes')) -notmatch '(?m)^z-Publish/\*\* binary\s*$') {
    $errors.Add('.gitattributes 必须包含 z-Publish/** binary')
}

# Windows PowerShell 5.1 按系统代码页读无 BOM 的脚本，中文注释与字符串会被读坏。
foreach ($script in Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.ps1' |
    Where-Object { $_.FullName -notmatch $generated }) {
    $head = @([IO.File]::ReadAllBytes($script.FullName) | Select-Object -First 3)
    if ($head.Count -lt 3 -or $head[0] -ne 0xEF -or $head[1] -ne 0xBB -or $head[2] -ne 0xBF) {
        $errors.Add("PowerShell 脚本必须带 UTF-8 BOM: $($script.FullName)")
    }
}

# 密钥绝不入库。判据是真实密钥的形状，不是维护一张豁免名单。
$secretPattern = 'sk-[0-9a-fA-F]{32,}'
foreach ($file in Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
    Where-Object {
        $_.FullName -notmatch '\\(?:bin|obj|\.git)\\' -and
        $_.Extension -in @('.md', '.json', '.cs', '.props', '.csproj', '.ps1', '.txt', '.yml', '.yaml')
    }) {
    foreach ($match in [regex]::Matches((Read-Text $file.FullName), $secretPattern)) {
        $errors.Add("疑似真实密钥入库: $($file.FullName) → $($match.Value.Substring(0, 6))…")
    }
}

# 现行文档里的本地 Markdown 链接必须指向存在的文件。
# 不要写指向别的仓的相对链接：F 盘工作区里它们必然失效。
foreach ($document in Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.md' |
    Where-Object { $_.FullName -notmatch $generated }) {
    $content = Read-Text $document.FullName
    foreach ($match in [regex]::Matches($content, '\]\((?<target>[^)#:]+)(?:#[^)]*)?\)')) {
        $target = $match.Groups['target'].Value.Trim()
        $resolved = Join-Path (Split-Path -Parent $document.FullName) $target
        if (-not (Test-Path -LiteralPath $resolved)) {
            $errors.Add("失效的本地链接: $($document.FullName) → $target")
        }
    }
}

if ($Instantiation) {
    if ($isTemplate) {
        $errors.Add('实例化项目的 template.isTemplate 必须为 false')
    }
    $textFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.md', '.json', '.props', '.csproj', '.cs', '.ps1') } |
        Where-Object { $_.FullName -notmatch $generated -and $_.Name -notin @('AGENTS.md', 'Test-ProjectContract.ps1') }
    foreach ($file in $textFiles) {
        $content = Read-Text $file.FullName
        if ($content -match '\{\{.+?\}\}') {
            $errors.Add("存在未实例化占位符: $($file.FullName)")
        }
        if ($content -match 'Exemplum') {
            $errors.Add("残留模板名 Exemplum（先运行 b-Code\New-ModuleFromTemplate.ps1）: $($file.FullName)")
        }
    }

    # 宿主发布表不登记，vulcan.dev.start 照样开得出工作区，submit 却会拒收——提前提醒。
    $registry = [IO.Path]::GetFullPath((Join-Path $repoRoot '..\2026-023-HistoryVulcan\b-Code-Eng\pipeline\module-publish.manifest.json'))
    if (Test-Path -LiteralPath $registry) {
        $registered = @((Read-Text $registry | ConvertFrom-Json).modules | Where-Object { $_.name -eq $moduleName })
        if ($registered.Count -eq 0) {
            $warnings.Add("宿主发布表还没登记 ${moduleName}：$registry；登记前 vulcan.dev.submit 会拒收")
        }
    }
}

$warnings | ForEach-Object { Write-Warning $_ }
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

$mode = if ($isTemplate) { 'template' } else { 'module' }
Write-Output "$moduleName project contract: PASS ($mode; $moduleVersion)"
