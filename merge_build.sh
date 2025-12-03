#!/bin/bash
# 合并后的构建脚本，支持APK和XAPK格式
# 公共变量参数 部分从Github Action中传入
BUILD_TOOLS_DIR=$(find ${ANDROID_HOME}/build-tools -maxdepth 1 -type d | sort -V | tail -n 1)
AAPT_PATH="${BUILD_TOOLS_DIR}/aapt"
DOWNLOAD_DIR="."
GAME_SERVER=$1
APK_URL=$2
BUILD_TYPE="APK" # 默认构建类型

# 检查参数
CHECK_PARAM() {
    if [ -z "${GAME_SERVER}" ]; then
        echo "服务器名称不能为空"
        exit 1
    fi

    if ! echo "${GAME_SERVER}" | grep -q "^[a-zA-Z0-9]*$"; then
        echo "服务器参数包含非英文数字字符,请重新输入"
        exit 1
    fi

    # 检测是否需要使用XAPK构建模式
    # 对于国际服务器（EN、JP、KR）和TW服务器，使用XAPK模式
    # 这些服务器通常通过apkeep直接下载，不需要APK_URL参数
    case "${GAME_SERVER}" in
        "TW" | "EN" | "JP" | "KR")
            BUILD_TYPE="XAPK"
            echo "检测到需要使用XAPK构建模式: ${GAME_SERVER}"
            ;;
        *)
            # 其他服务器需要提供APK下载链接
            if [ -z "${APK_URL}" ]; then
                echo "APK下载链接不能为空"
                exit 1
            fi
            BUILD_TYPE="APK"
            echo "使用标准APK构建模式: ${GAME_SERVER}"
            ;;
    esac
}

# 设置包名和文件名（XAPK模式使用）
SET_BUNDLE_ID() {
    case "$GAME_SERVER" in
        "TW")
            GAME_BUNDLE_ID="com.hkmanjuu.azurlane.gp"
            ;;
        "EN")
            GAME_BUNDLE_ID="com.YoStarEN.AzurLane"
            ;;
        "JP")
            GAME_BUNDLE_ID="com.YoStarJP.AzurLane"
            ;;
        "KR")
            GAME_BUNDLE_ID="kr.txwy.and.blhx"
            ;;
    esac
    APK_FILENAME="${GAME_BUNDLE_ID}.apk"
    echo "已设置包名为: ${GAME_BUNDLE_ID}"
}

# 下载apkeep（XAPK模式使用）
DOWNLOAD_APKEEP() {
    local OWNER="EFForg"
    local REPO="apkeep"
    local LIB_PLATFORM="x86_64-unknown-linux-gnu"
    local FILENAME="apkeep"

    echo "正在下载apkeep工具..."
    local API_RESPONSE=$(curl -s "https://api.github.com/repos/${OWNER}/${REPO}/releases/latest")
    local DOWNLOAD_LINK=$(echo "${API_RESPONSE}" | jq -r ".assets[] | select(.name | contains(\"${LIB_PLATFORM}\")) | .browser_download_url" | head -n 1)
    if [ -z "${DOWNLOAD_LINK}" ] || [ "${DOWNLOAD_LINK}" == "null" ]; then
        echo "无法找到Apkeep下载链接"
        exit 1
    fi

    curl -L -o "${DOWNLOAD_DIR}/${FILENAME}" "${DOWNLOAD_LINK}"
    if [ $? -eq 0 ]; then
        echo "Apkeep下载成功！文件保存至：${DOWNLOAD_DIR}/${FILENAME}"
        chmod +x "${DOWNLOAD_DIR}/${FILENAME}"
    else
        echo "Apkeep下载失败，请重试"
        exit 1
    fi
}

# 下载ApkTool
DOWNLOAD_APKTOOL() {
    local OWNER="iBotPeaches"
    local REPO="Apktool"
    local FILENAME="apktool.jar"

    echo "正在下载Apktool..."
    local API_RESPONSE=$(curl -s "https://api.github.com/repos/${OWNER}/${REPO}/releases/latest")
    local DOWNLOAD_LINK=$(echo "${API_RESPONSE}" | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' | head -n 1)
    if [ -z "${DOWNLOAD_LINK}" ] || [ "${DOWNLOAD_LINK}" == "null" ]; then
        echo "无法找到Apktool下载链接"
        exit 1
    fi

    curl -L -o "${DOWNLOAD_DIR}/${FILENAME}" "${DOWNLOAD_LINK}"
    if [ $? -eq 0 ]; then
        echo "Apktool下载成功！文件保存至：${DOWNLOAD_DIR}/${FILENAME}"
    else
        echo "Apktool下载失败，请重试"
        exit 1
    fi
}

# 下载 Mod Patch 文件并解压
DOWNLOAD_MOD_MENU() {
    local OWNER="JMBQ"
    local REPO="azurlane"
    local FILENAME="MOD_MENU.zip"

    echo "正在下载MOD补丁..."
    local API_RESPONSE=$(curl -s "https://api.github.com/repos/${OWNER}/${REPO}/releases/latest")
    local JMBQ_VERSION=$(echo "${API_RESPONSE}" | jq -r '.tag_name')
    local DOWNLOAD_LINK=$(echo "${API_RESPONSE}" | jq -r '.assets[0].browser_download_url')

    if [ -z "${DOWNLOAD_LINK}" ] || [ "${DOWNLOAD_LINK}" == "null" ]; then
        echo "无法获取MOD Patch文件下载链接"
        exit 1
    fi

    curl -L -o "${DOWNLOAD_DIR}/${FILENAME}" "${DOWNLOAD_LINK}"
    if [ $? -eq 0 ]; then
        echo "补丁下载成功！文件保存至：${DOWNLOAD_DIR}/${FILENAME}"
    else
        echo "补丁下载失败，请重试"
        exit 1
    fi

    unzip -q "${DOWNLOAD_DIR}/${FILENAME}" -d "${DOWNLOAD_DIR}/JMBQ"
    if [ $? -ne 0 ]; then
        echo "错误: 解压 ${FILENAME} 失败！"
        exit 1
    fi

    echo "JMBQ_VERSION=${JMBQ_VERSION}" >> "${GITHUB_ENV}"
}

# 下载APK（通用函数，根据构建类型执行不同的下载逻辑）
#DOWNLOAD_APK() {
#    if [ "${BUILD_TYPE}" = "XAPK" ]; then
#        # XAPK模式下载逻辑
#        echo "正在使用apkeep下载XAPK..."
#        "${DOWNLOAD_DIR}/apkeep" -a "${GAME_BUNDLE_ID}" "${DOWNLOAD_DIR}/"
#        if [ $? -ne 0 ]; then
#            echo "XAPK 下载失败！"
#            exit 1
#        fi
#        echo "XAPK [${GAME_BUNDLE_ID}.xapk] 下载成功！"
#        echo "正在从 XAPK 中提取文件..."
#        unzip -o "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.xapk" -d "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}"
#        if [ $? -ne 0 ]; then
#            echo "错误: 解压失败！"
#            exit 1
#        fi
#       mv "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}/${GAME_BUNDLE_ID}.apk" "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
#    else
#        # 普通APK模式下载逻辑
#        APK_FILENAME="${GAME_SERVER}.apk"
#        echo "正在下载APK..."
#        curl -L -o "${DOWNLOAD_DIR}/${APK_FILENAME}" "${APK_URL}"
#        if [ $? -ne 0 ]; then
#            echo "APK下载失败"
#            exit 1
#        fi
#        echo "APK [${APK_FILENAME}] 下载完成"
#    fi
#}

# 下载APK（通用函数，根据构建类型执行不同的下载逻辑）
DOWNLOAD_APK() {
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        # XAPK模式下载逻辑保持不变
        echo "正在使用apkeep下载XAPK..."
        "${DOWNLOAD_DIR}/apkeep" -a "${GAME_BUNDLE_ID}" "${DOWNLOAD_DIR}/"
        if [ $? -ne 0 ]; then
            echo "XAPK 下载失败！"
            exit 1
        fi
        echo "XAPK [${GAME_BUNDLE_ID}.xapk] 下载成功！"
        echo "正在从 XAPK 中提取文件..."
        unzip -o "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.xapk" -d "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}"
        if [ $? -ne 0 ]; then
            echo "错误: 解压失败！"
            exit 1
        fi
        mv "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}/${GAME_BUNDLE_ID}.apk" "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
    else
        # 普通APK模式下载逻辑
        APK_FILENAME="${GAME_SERVER}.apk"
        echo "正在下载APK..."
        
        # 检查是否为Google Drive链接
        if echo "${APK_URL}" | grep -q "drive.google.com"; then
            echo "检测到Google Drive链接，使用gdown下载..."
            
            # 提取文件ID
            FILE_ID=$(echo "${APK_URL}" | sed -n 's/.*\/d\/\([^\/]*\)\/.*/\1/p')
            if [ -z "${FILE_ID}" ]; then
                FILE_ID=$(echo "${APK_URL}" | sed -n 's/.*id=\([^&]*\).*/\1/p')
            fi
            
            if [ -z "${FILE_ID}" ]; then
                echo "无法从Google Drive链接中提取文件ID"
                exit 1
            fi
            
            echo "提取的文件ID: ${FILE_ID}"
            
            # 使用gdown下载
            if command -v gdown &> /dev/null; then
                echo "使用gdown下载文件..."
                gdown "https://drive.google.com/uc?id=${FILE_ID}" -O "${DOWNLOAD_DIR}/${APK_FILENAME}"
                
                if [ $? -ne 0 ]; then
                    echo "gdown下载失败，尝试备用方法..."
                    # 备用方法：使用带有确认处理的curl
                    DOWNLOAD_FROM_GOOGLE_DRIVE_WITH_CONFIRMATION
                fi
            else
                echo "gdown未安装，使用备用方法..."
                DOWNLOAD_FROM_GOOGLE_DRIVE_WITH_CONFIRMATION
            fi
        else
            # 非Google Drive链接，直接下载
            curl -L -o "${DOWNLOAD_DIR}/${APK_FILENAME}" "${APK_URL}"
        fi
        
        if [ $? -ne 0 ]; then
            echo "APK下载失败"
            exit 1
        fi
        
        # 验证下载的文件大小
        FILE_SIZE=$(stat -c%s "${DOWNLOAD_DIR}/${APK_FILENAME}" 2>/dev/null || stat -f%z "${DOWNLOAD_DIR}/${APK_FILENAME}" 2>/dev/null)
        echo "下载完成，文件大小: ${FILE_SIZE} 字节"
        
        if [ "${FILE_SIZE}" -lt 10485760 ]; then  # 小于10MB
            echo "警告：下载的文件可能不是有效的APK文件（大小: ${FILE_SIZE} 字节）"
            echo "文件前100个字符："
            head -c 100 "${DOWNLOAD_DIR}/${APK_FILENAME}"
            echo ""
            
            # 检查是否是HTML文件
            if grep -q "<html\|<!DOCTYPE\|http-equiv\|Google Drive" "${DOWNLOAD_DIR}/${APK_FILENAME}" 2>/dev/null; then
                echo "错误：下载的是HTML页面，不是APK文件"
                echo "可能是Google Drive的病毒扫描警告页面"
                echo "建议："
                echo "1. 将文件上传到其他平台（如GitHub Releases）"
                echo "2. 或者使用XAPK模式（如果支持）"
                exit 1
            fi
        fi
        
        echo "APK [${APK_FILENAME}] 下载完成"
    fi
}

# 删除原始XAPK（XAPK模式使用）
DELETE_ORGINAL_XAPK() {
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        echo "删除原始XAPK文件..."
        rm -rf "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.xapk"
    fi
}

# 验证APK
VERIFY_APK() {
    local APK_TO_VERIFY
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        APK_TO_VERIFY="${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
    else
        APK_TO_VERIFY="${DOWNLOAD_DIR}/${GAME_SERVER}.apk"
    fi
    
    echo "正在验证APK: ${APK_TO_VERIFY}"
    [ ! -f "${APK_TO_VERIFY}" ] && { echo "APK文件未找到"; exit 1; }
    
    local FILE_SIZE=$(stat -f%z "${APK_TO_VERIFY}" 2>/dev/null || stat -c%s "${APK_TO_VERIFY}" 2>/dev/null)
    [ "${FILE_SIZE}" -lt 1024 ] && { echo "APK文件大小异常"; exit 1; }
    unzip -t "${APK_TO_VERIFY}" >/dev/null 2>&1 || { echo "APK文件损坏"; exit 1; }
    echo "APK验证通过"
}

# APK 解包
DECODE_APK() {
    local APK_TO_DECODE
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        APK_TO_DECODE="${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
    else
        APK_TO_DECODE="${DOWNLOAD_DIR}/${GAME_SERVER}.apk"
    fi
    
    echo "APK反编译: ${APK_TO_DECODE}"
    java -jar "${DOWNLOAD_DIR}/apktool.jar" d -f "${APK_TO_DECODE}" -o "${DOWNLOAD_DIR}/DECODE_Output"
    if [ $? -ne 0 ]; then
        echo "错误: APK 反编译失败！"
        exit 1
    fi
    echo "反编译完成。"
}

# 删除源APK
DELETE_ORGINAL_APK() {
    local APK_TO_DELETE
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        APK_TO_DELETE="${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
    else
        APK_TO_DELETE="${DOWNLOAD_DIR}/${GAME_SERVER}.apk"
    fi
    
    echo "删除原始APK文件..."
    rm -rf "${APK_TO_DELETE}"
}

# 合入MOD
<< patch
PATCH_APK() {
    echo "正在合入MOD补丁..."
    cp -r "${DOWNLOAD_DIR}/JMBQ/assets/." "${DOWNLOAD_DIR}/DECODE_Output/assets/"
    if [ $? -ne 0 ]; then
        echo "错误: 复制资源文件失败！"
        exit 1
    fi
    echo "复制资源文件完成"

    local MAX_CLASS_NUM=$(find "${DOWNLOAD_DIR}/DECODE_Output/" -maxdepth 1 -type d -name "smali_classes*" 2>/dev/null | sed 's/.*smali_classes//' | sort -n | tail -1)
    MAX_CLASS_NUM=${MAX_CLASS_NUM:-3}
    local NEW_CLASS_NUM=$((MAX_CLASS_NUM + 1))
    local NEW_SMALI_DIR="smali_classes${NEW_CLASS_NUM}"
    local SRC_DIR=$(find "${DOWNLOAD_DIR}/JMBQ" -maxdepth 1 -type d -name "smali_classes*")

    if [ -z "${SRC_DIR}" ]; then
        echo "错误: MOD 补丁目录中未找到 smali_classes 目录！"
        exit 1
    fi

    cp -r "${SRC_DIR}" "${DOWNLOAD_DIR}/DECODE_Output/${NEW_SMALI_DIR}" || {
        echo "错误: 复制 smali 文件失败！"
        exit 1
    }
    echo "smali文件复制完成"

    local SMALI_FILE=$(find "${DOWNLOAD_DIR}/DECODE_Output" -type f -name "UnityPlayerActivity.smali")
    if [ -z "${SMALI_FILE}" ]; then
        echo "错误: UnityPlayerActivity.smali 文件未找到！"
        exit 1
    fi
    echo "已找到 UnityPlayerActivity.smali 文件，路径为: ${SMALI_FILE}"

    local LINE_NUM=$(grep -n ".method public constructor <init>()V" "${SMALI_FILE}" | cut -d: -f1)
    [ -z "${LINE_NUM}" ] && {
        echo "未找到构造函数"
        exit 1
    }

    echo "正在修改 ${SMALI_FILE} 文件..."
    sed -i -e "/\.method public constructor <init>()V/,/\.end method/{" \
           -e "/\.locals 0/a\    invoke-static {}, Lcom/android/support/Main;->Start()V" \
           -e "}" "${SMALI_FILE}" || {
        echo "错误：添加smali代码失败，请检查文件路径、权限或文件内容格式。"
        exit 1
    }
    echo "smali代码添加成功！"

    echo "正在修改 AndroidManifest.xml 文件..."
    local MANIFEST_FILE="${DOWNLOAD_DIR}/DECODE_Output/AndroidManifest.xml"
    sed -i 's#</application>#    <service android:name="com.android.support.Launcher" android:enabled="true" android:exported="false" android:stopWithTask="true"/>\n    </application>\n    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>#' "${MANIFEST_FILE}" || {
        echo "错误：修改 AndroidManifest.xml 文件失败，请检查文件路径、权限或文件内容格式。"
        exit 1
    }
    echo "修改成功！"
    echo "补丁完成。"
}
patch

# 合入MOD
PATCH_APK() {
    echo "正在合入MOD补丁..."
    
    # 1. 复制assets文件夹（如果存在）
    if [ -d "${DOWNLOAD_DIR}/JMBQ/assets" ]; then
        cp -r "${DOWNLOAD_DIR}/JMBQ/assets/." "${DOWNLOAD_DIR}/DECODE_Output/assets/"
        echo "复制资源文件完成"
    else
        echo "警告：assets目录不存在，跳过资源文件复制"
    fi

    # 2. 查找smali目录
    local SRC_DIR=""
    
    # 先尝试查找smali_classes目录
    SRC_DIR=$(find "${DOWNLOAD_DIR}/JMBQ" -maxdepth 2 -type d -name "smali_classes*" | head -1)
    
    # 如果没有找到，尝试查找smali目录
    if [ -z "${SRC_DIR}" ]; then
        SRC_DIR=$(find "${DOWNLOAD_DIR}/JMBQ" -maxdepth 2 -type d -name "smali" | head -1)
    fi
    
    # 如果仍然没有找到，尝试在JMBQ根目录下查找
    if [ -z "${SRC_DIR}" ]; then
        # 检查JMBQ目录下是否有直接的smali文件
        if [ -d "${DOWNLOAD_DIR}/JMBQ/smali" ] || [ -n "$(find "${DOWNLOAD_DIR}/JMBQ" -maxdepth 1 -name 'smali*' -type d)" ]; then
            SRC_DIR="${DOWNLOAD_DIR}/JMBQ"
        fi
    fi

    if [ -z "${SRC_DIR}" ]; then
        echo "错误: MOD 补丁目录中未找到 smali 目录！"
        echo "检查 JMBQ 目录结构："
        find "${DOWNLOAD_DIR}/JMBQ" -type f -name "*.smali" | head -10
        find "${DOWNLOAD_DIR}/JMBQ" -type d | head -20
        exit 1
    fi

    echo "找到MOD补丁目录: ${SRC_DIR}"
    
    # 3. 复制smali文件
    # 首先检查目标APK中已存在的最大smali_classes编号
    local MAX_CLASS_NUM=$(find "${DOWNLOAD_DIR}/DECODE_Output/" -maxdepth 1 -type d -name "smali_classes*" 2>/dev/null | sed 's/.*smali_classes//' | sort -n | tail -1)
    MAX_CLASS_NUM=${MAX_CLASS_NUM:-3}
    local NEW_CLASS_NUM=$((MAX_CLASS_NUM + 1))
    local NEW_SMALI_DIR="smali_classes${NEW_CLASS_NUM}"
    
    echo "目标APK中最大smali_classes编号: ${MAX_CLASS_NUM}"
    echo "将创建新的smali目录: ${NEW_SMALI_DIR}"
    
    # 复制smali文件
    if [ -d "${SRC_DIR}/smali" ] || [ -n "$(find "${SRC_DIR}" -maxdepth 1 -name 'smali*' -type d)" ]; then
        # 如果源目录下有明确的smali或smali_classes目录
        for dir in "${SRC_DIR}"/smali*; do
            if [ -d "${dir}" ]; then
                local dir_name=$(basename "${dir}")
                echo "复制目录: ${dir_name}"
                cp -r "${dir}" "${DOWNLOAD_DIR}/DECODE_Output/${dir_name}"
            fi
        done
    else
        # 如果源目录直接包含smali文件
        echo "复制整个补丁目录到: ${NEW_SMALI_DIR}"
        mkdir -p "${DOWNLOAD_DIR}/DECODE_Output/${NEW_SMALI_DIR}"
        
        # 查找并复制所有.smali文件
        find "${SRC_DIR}" -name "*.smali" -exec cp --parents {} "${DOWNLOAD_DIR}/DECODE_Output/${NEW_SMALI_DIR}/" \;
        
        if [ $? -ne 0 ]; then
            echo "尝试直接复制整个目录..."
            cp -r "${SRC_DIR}/." "${DOWNLOAD_DIR}/DECODE_Output/${NEW_SMALI_DIR}/" 2>/dev/null || true
        fi
    fi
    
    echo "smali文件复制完成"

    # 4. 修改UnityPlayerActivity.smali
    local SMALI_FILE=$(find "${DOWNLOAD_DIR}/DECODE_Output" -type f -name "UnityPlayerActivity.smali")
    if [ -z "${SMALI_FILE}" ]; then
        echo "警告: UnityPlayerActivity.smali 文件未找到，尝试其他名称..."
        # 尝试其他可能的文件名
        SMALI_FILE=$(find "${DOWNLOAD_DIR}/DECODE_Output" -type f -name "*Unity*Activity.smali" | head -1)
        
        if [ -z "${SMALI_FILE}" ]; then
            echo "错误: 未找到Unity相关的Activity smali文件！"
            echo "找到的smali文件："
            find "${DOWNLOAD_DIR}/DECODE_Output" -type f -name "*.smali" | head -20
            exit 1
        fi
    fi
    
    echo "已找到Activity smali文件，路径为: ${SMALI_FILE}"

    # 检查是否已经添加过代码
    if grep -q "invoke-static {}, Lcom/android/support/Main;->Start()V" "${SMALI_FILE}"; then
        echo "MOD代码已经添加，跳过修改"
    else
        local LINE_NUM=$(grep -n ".method public constructor <init>()V" "${SMALI_FILE}" | cut -d: -f1)
        if [ -z "${LINE_NUM}" ]; then
            echo "警告: 未找到构造函数，尝试其他方法..."
            # 尝试在onCreate方法中添加
            LINE_NUM=$(grep -n ".method protected onCreate(Landroid/os/Bundle;)V" "${SMALI_FILE}" | cut -d: -f1)
            
            if [ -n "${LINE_NUM}" ]; then
                echo "在onCreate方法中添加代码"
                sed -i "/\.method protected onCreate(Landroid\/os\/Bundle;)V/,/\.end method/{
                    /\.locals /a\    invoke-static {}, Lcom/android/support/Main;->Start()V
                }" "${SMALI_FILE}" || {
                    echo "错误：添加smali代码失败"
                    exit 1
                }
            else
                echo "错误：未找到合适的插入点"
                exit 1
            fi
        else
            echo "在构造函数中添加代码"
            sed -i "/\.method public constructor <init>()V/,/\.end method/{
                /\.locals /a\    invoke-static {}, Lcom/android/support/Main;->Start()V
            }" "${SMALI_FILE}" || {
                echo "错误：添加smali代码失败，请检查文件路径、权限或文件内容格式。"
                exit 1
            }
        fi
        echo "smali代码添加成功！"
    fi

    # 5. 修改 AndroidManifest.xml 文件
    echo "正在修改 AndroidManifest.xml 文件..."
    local MANIFEST_FILE="${DOWNLOAD_DIR}/DECODE_Output/AndroidManifest.xml"
    
    # 检查是否已经添加过
    if ! grep -q "com.android.support.Launcher" "${MANIFEST_FILE}"; then
        sed -i 's#</application>#    <service android:name="com.android.support.Launcher" android:enabled="true" android:exported="false" android:stopWithTask="true"/>\n    </application>\n    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>#' "${MANIFEST_FILE}" || {
            echo "错误：修改 AndroidManifest.xml 文件失败，请检查文件路径、权限或文件内容格式。"
            exit 1
        }
        echo "AndroidManifest.xml 修改成功！"
    else
        echo "AndroidManifest.xml 已经包含MOD服务，跳过修改"
    fi
    
    echo "补丁完成。"
}

# 打包APK
BUILD_APK() {
    local OUTPUT_APK
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        OUTPUT_APK="${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
    else
        OUTPUT_APK="${DOWNLOAD_DIR}/${GAME_SERVER}.apk"
    fi
    
    echo "正在重新构建已打补丁的 APK 文件: ${OUTPUT_APK}"
    java -jar "${DOWNLOAD_DIR}/apktool.jar" b -f "${DOWNLOAD_DIR}/DECODE_Output" -o "${OUTPUT_APK}"
    if [ $? -ne 0 ]; then
        echo "错误: APK 构建失败！"
        exit 1
    fi
    echo "APK 构建成功"
}

# 优化并签名APK
OPTIMIZE_AND_SIGN_APK() {
    export PATH=${PATH}:${BUILD_TOOLS_DIR}
    local KEY_DIR="${DOWNLOAD_DIR}/key/"
    local PRIVATE_KEY="${KEY_DIR}testkey.pk8"
    local CERTIFICATE="${KEY_DIR}testkey.x509.pem"
    local INPUT_APK
    local UNSIGNED_APK
    local FINAL_APK
    
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        INPUT_APK="${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
        UNSIGNED_APK="${GAME_BUNDLE_ID}.unsigned.apk"
    else
        INPUT_APK="${DOWNLOAD_DIR}/${GAME_SERVER}.apk"
        UNSIGNED_APK="${GAME_SERVER}.unsigned.apk"
    fi
    
    local OUTPUT_APK="${DOWNLOAD_DIR}/${UNSIGNED_APK}"
    local FINAL_APK="${INPUT_APK}"

    if [ ! -f "${INPUT_APK}" ]; then
        echo "错误：找不到输入APK文件: ${INPUT_APK}"
        exit 1
    fi

    if [ ! -f "${PRIVATE_KEY}" ] || [ ! -f "${CERTIFICATE}" ]; then
        echo "错误：找不到签名密钥文件"
        echo "请确保以下文件存在："
        echo "  - ${PRIVATE_KEY}"
        echo "  - ${CERTIFICATE}"
        exit 1
    else
        echo "已找到签名密钥："
        echo "  - ${PRIVATE_KEY}"
        echo "  - ${CERTIFICATE}"
    fi

    echo "正在优化APK..."
    if zipalign -f 4 "${INPUT_APK}" "${OUTPUT_APK}"; then
        echo "优化成功"
        rm "${INPUT_APK}"

        echo "正在签名APK..."
        if apksigner sign --key "${PRIVATE_KEY}" --cert "${CERTIFICATE}" "${OUTPUT_APK}"; then
            echo "签名成功"
            mv "${OUTPUT_APK}" "${FINAL_APK}"
        else
            echo "签名失败"
            exit 1
        fi
    else
        echo "优化失败"
        exit 1
    fi
}

# 获取并传回游戏版本
GET_GAME_VERSION() {
    local APK_TO_CHECK
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        APK_TO_CHECK="${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
    else
        APK_TO_CHECK="${DOWNLOAD_DIR}/${GAME_SERVER}.apk"
    fi
    
    if [ -f "${APK_TO_CHECK}" ]; then
        if [ -f "${AAPT_PATH}" ]; then
            GAME_VERSION=$("${AAPT_PATH}" dump badging "${APK_TO_CHECK}" | grep "versionName" | sed "s/.*versionName='\([^']*\)'.*/\1/" | head -1)
            if [ -z "${GAME_VERSION}" ] || [ "${GAME_VERSION}" = "''" ]; then
                GAME_VERSION="未知"
                echo "警告：无法从APK提取版本信息"
            fi
        else
            echo "错误：找不到aapt工具: ${AAPT_PATH}"
        fi
    else
        echo "错误：APK文件不存在: ${APK_TO_CHECK}"
    fi
    echo "VERSION=${GAME_VERSION}" >> "${GITHUB_ENV}"
    echo "游戏版本: ${GAME_VERSION}"
}

# 重命名APK（APK模式使用）
RENAME_APK() {
    if [ "${BUILD_TYPE}" = "APK" ] && [ -f "${DOWNLOAD_DIR}/${GAME_SERVER}.apk" ]; then
        if [ -f "${AAPT_PATH}" ]; then
            PACKAGE_NAME=$("${AAPT_PATH}" dump badging "${DOWNLOAD_DIR}/${GAME_SERVER}.apk" | grep "package: name=" | cut -d"'" -f2 | head -1)
            if [ -z "${PACKAGE_NAME}" ] || [ "${PACKAGE_NAME}" = "''" ]; then
                PACKAGE_NAME="${GAME_SERVER}"
                echo "警告：无法从APK提取包名，使用服务器名称作为包名"
            fi
            mv "${DOWNLOAD_DIR}/${GAME_SERVER}.apk" "${DOWNLOAD_DIR}/${PACKAGE_NAME}.apk"
            echo "重命名成功 [${PACKAGE_NAME}.apk]"
        else
            echo "错误：找不到aapt工具: ${AAPT_PATH}"
        fi
    fi
}

# 移动修改后的APK到源目录并重新打包XAPK（XAPK模式使用）
REPACK_XAPK() {
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        echo "正在重新打包XAPK..."
        mkdir -p "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}"
        mv -f "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk" "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}/${GAME_BUNDLE_ID}.apk"
        cd "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}" && zip -r "${GAME_BUNDLE_ID}.xapk" *
        cd - > /dev/null
        mv "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}/${GAME_BUNDLE_ID}.xapk" "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.xapk"
        echo "XAPK重新打包完成"
    fi
}

# 生成7z分卷压缩包
CREATE_SPLIT_ARCHIVES() {
    local FINAL_FILE
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        FINAL_FILE="${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.xapk"
    else
        if [ -f "${DOWNLOAD_DIR}/${PACKAGE_NAME}.apk" ]; then
            FINAL_FILE="${DOWNLOAD_DIR}/${PACKAGE_NAME}.apk"
        else
            FINAL_FILE="${DOWNLOAD_DIR}/${GAME_SERVER}.apk"
        fi
    fi
    
    if [ ! -f "${FINAL_FILE}" ]; then
        echo "错误: 最终文件未找到: ${FINAL_FILE}"
        exit 1
    fi
    echo "正在压缩 ${FINAL_FILE}"
    7z a -v800M "${GAME_SERVER}-V.${GAME_VERSION}.7z" "${FINAL_FILE}" || {
        echo "错误: 7z 压缩失败！"
        exit 1
    }
    echo "分卷压缩完成: ${GAME_SERVER}-V.${GAME_VERSION}.7z"
}

# 打印Logo
PRINT_LOGO() {
    cat << "EOF"

 ________  ________  ___  ___  ________  ___       ________  ________   _______              ___  _____ ______   ________  ________      
|\   __  \|\_____  \|\  \|\  \|\   __  \|\  \     |\   __  \|\   ___  \|\  ___ \            |\  \|\   _ \  _   \|\   __  \|\   __  \     
\ \  \|\  \\___/  /\ \  \\  \ \  \|\  \ \  \    \ \  \|\  \ \  \\ \  \ \   __/|           \ \  \ \  \\__\ \  \ \  \|\ /\ \  \|\  \    
 \ \   __  \   /  / /\ \  \\  \ \   _  _\ \  \    \ \   __  \ \  \\ \  \ \  \_|/__       __ \ \  \ \  \\|__| \  \ \   __  \ \  \\  \\  
  \ \  \ \  \ /  /_/__\ \  \\  \ \  \\  \\ \  \____\ \  \ \  \ \  \\ \  \ \  \_|\ \     |\  \\\_\  \ \  \    \ \  \ \  \|\  \ \  \\  \\  
   \ \__\ \__\\________\ \_______\ \__\\ _\\ \_______\ \__\ \__\ \__\\ \__\ \_______\    \ \________\ \__\    \ \__\ \_______\ \_____  \ 
    \|__|\|__\|\|_______|\|_______|\|__|\|__\|_______|\|__|\|__|\|__| \|__\|_______|     \|________|\|__|     \|__\|_______|\|___| \__\
                                                                                                                                    \|__|
                                                                                                                                         
                                                                                                                                                                                                 
EOF
}

# 主执行函数
main() {
    PRINT_LOGO
    CHECK_PARAM
    
    # 根据构建类型执行不同的流程
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        # XAPK构建流程
        SET_BUNDLE_ID
        DOWNLOAD_APKEEP
        DOWNLOAD_APKTOOL
        DOWNLOAD_MOD_MENU
        DOWNLOAD_APK
        DELETE_ORGINAL_XAPK
        VERIFY_APK
        DECODE_APK
        DELETE_ORGINAL_APK
        PATCH_APK
        BUILD_APK
        OPTIMIZE_AND_SIGN_APK
        GET_GAME_VERSION
        REPACK_XAPK
    else
        # APK构建流程
        DOWNLOAD_APKTOOL
        DOWNLOAD_MOD_MENU
        DOWNLOAD_APK
        VERIFY_APK
        DECODE_APK
        DELETE_ORGINAL_APK
        PATCH_APK
        BUILD_APK
        OPTIMIZE_AND_SIGN_APK
        RENAME_APK
        GET_GAME_VERSION
    fi
    
    # 共同的后续步骤
    CREATE_SPLIT_ARCHIVES
    echo "构建完成！构建类型: ${BUILD_TYPE}"
}

# 执行主函数
main
