#!/bin/bash
set -e

echo "🚀 Exportando ferramentas Qt6 + KF6 para o host..."

# Criar estrutura de saída
mkdir -p /mnt/dev-tools/{bin,lib,qml,plugins}

# Binários essenciais
echo "📦 Copiando binários..."
# qmllint pode estar em vários lugares no openSUSE
for qmllint_path in /usr/lib64/qt6/bin/qmllint /usr/bin/qmllint /usr/lib/qt6/bin/qmllint; do
    if [ -f "$qmllint_path" ]; then
        cp "$qmllint_path" /mnt/dev-tools/bin/
        echo "  ✓ qmllint encontrado em: $qmllint_path"
        break
    fi
done
# qmlformat pode estar em vários lugares
for qmlformat_path in /usr/lib64/qt6/bin/qmlformat /usr/bin/qmlformat /usr/lib/qt6/bin/qmlformat; do
    if [ -f "$qmlformat_path" ]; then
        cp "$qmlformat_path" /mnt/dev-tools/bin/
        echo "  ✓ qmlformat encontrado em: $qmlformat_path"
        break
    fi
done
# qmake6 pode estar em vários lugares
for qmake_path in /usr/lib64/qt6/bin/qmake6 /usr/bin/qmake6 /usr/lib/qt6/bin/qmake6 /usr/bin/qmake; do
    if [ -f "$qmake_path" ]; then
        cp "$qmake_path" /mnt/dev-tools/bin/
        echo "  ✓ qmake encontrado em: $qmake_path"
        break
    fi
done

# Bibliotecas Qt6 (de /lib64 e /usr/lib64)
echo "📚 Copiando bibliotecas Qt6..."
find /lib64 /usr/lib64 -name "libQt6*.so*" -exec cp {} /mnt/dev-tools/lib/ \; 2>/dev/null || true
if [ -d /usr/lib64/qt6 ]; then
    cp -r /usr/lib64/qt6 /mnt/dev-tools/ 2>/dev/null || true
fi

# Bibliotecas ICU (necessárias para Qt6)
echo "📚 Copiando bibliotecas ICU..."
for icu_lib in /lib64/libicu*.so* /usr/lib64/libicu*.so*; do
    if [ -f "$icu_lib" ]; then
        cp "$icu_lib" /mnt/dev-tools/lib/ 2>/dev/null || true
    fi
done

# Outras bibliotecas essenciais do sistema
echo "📚 Copiando outras bibliotecas essenciais..."
for lib in libpcre2-16 libdouble-conversion libharfbuzz libfreetype libpng16 libjpeg; do
    find /lib64 -name "${lib}*.so*" -exec cp {} /mnt/dev-tools/lib/ \; 2>/dev/null || true
    find /usr/lib64 -name "${lib}*.so*" -exec cp {} /mnt/dev-tools/lib/ \; 2>/dev/null || true
done

# QML modules
echo "🎨 Copiando módulos QML..."
if [ -d /usr/lib64/qt6/qml ]; then
    cp -r /usr/lib64/qt6/qml/* /mnt/dev-tools/qml/ 2>/dev/null || true
fi
if [ -d /usr/share/kf6/qml ]; then
    cp -r /usr/share/kf6/qml/* /mnt/dev-tools/qml/ 2>/dev/null || true
fi

# Plugins Qt (incluindo qmltooling que é necessário para qmllint)
echo "🔌 Copiando plugins Qt..."
if [ -d /usr/lib64/qt6/plugins ]; then
    cp -r /usr/lib64/qt6/plugins/* /mnt/dev-tools/plugins/ 2>/dev/null || true
fi
# Garantir que qmltooling está copiado (necessário para qmllint funcionar)
if [ -d /usr/lib64/qt6/plugins/qmltooling ] && [ ! -d /mnt/dev-tools/plugins/qmltooling ]; then
    cp -r /usr/lib64/qt6/plugins/qmltooling /mnt/dev-tools/plugins/ 2>/dev/null || true
fi

# Permissões
chmod +x /mnt/dev-tools/bin/* 2>/dev/null || true

echo "✅ Exportação completa!"
echo "Ferramentas disponíveis em: /mnt/dev-tools"
echo "Binários: /mnt/dev-tools/bin"
echo "Bibliotecas: /mnt/dev-tools/lib"
echo "Módulos QML: /mnt/dev-tools/qml"
