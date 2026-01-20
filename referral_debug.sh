#!/bin/bash

# 🧪 Script de Debug para Sistema de Referral
# Uso: ./referral_debug.sh [comando]

set -e

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

function print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

function print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

function print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Verifica se Firebase está configurado
function check_firebase() {
    print_header "Verificando Firebase"
    
    if command -v firebase &> /dev/null; then
        print_success "Firebase CLI instalado"
        firebase --version
    else
        print_error "Firebase CLI não encontrado"
        echo "Instale com: npm install -g firebase-tools"
        exit 1
    fi
    
    if [ -f "firebase.json" ]; then
        print_success "firebase.json encontrado"
    else
        print_error "firebase.json não encontrado"
        exit 1
    fi
}

# Deploy da Cloud Function
function deploy_function() {
    print_header "Deploy Cloud Function"
    
    cd functions
    
    print_warning "Instalando dependências..."
    npm install
    
    print_warning "Fazendo deploy de onUserCreatedReferral..."
    firebase deploy --only functions:onUserCreatedReferral
    
    cd ..
    print_success "Deploy completo!"
}

# Verifica logs da Cloud Function
function check_logs() {
    print_header "Logs da Cloud Function"
    
    print_warning "Buscando logs recentes..."
    firebase functions:log --only onUserCreatedReferral --limit 50
}

# Verifica dados do Firestore
function check_firestore() {
    print_header "Verificando Firestore"
    
    read -p "Digite o userId para verificar: " user_id
    
    if [ -z "$user_id" ]; then
        print_error "userId não pode ser vazio"
        exit 1
    fi
    
    echo ""
    print_warning "Buscando documento Users/$user_id..."
    echo ""
    
    # Usar Firebase CLI para query (requer node.js script)
    node -e "
    const admin = require('firebase-admin');
    const serviceAccount = require('./service-account-key.json');
    
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
    
    const db = admin.firestore();
    
    async function checkUser() {
        const userDoc = await db.collection('Users').doc('$user_id').get();
        
        if (userDoc.exists) {
            const data = userDoc.data();
            console.log('✅ User encontrado:');
            console.log('   - fullName:', data.fullName);
            console.log('   - referrerId:', data.referrerId || 'null');
            console.log('   - referralInstallCount:', data.referralInstallCount || 0);
            console.log('   - user_is_vip:', data.user_is_vip || false);
            console.log('   - vipExpiresAt:', data.vipExpiresAt ? data.vipExpiresAt.toDate() : 'null');
            
            const referrals = await db.collection('ReferralInstalls')
                .where('referrerId', '==', '$user_id')
                .get();
            
            console.log('');
            console.log('✅ ReferralInstalls:', referrals.size, 'conversões');
            
            referrals.forEach(doc => {
                const data = doc.data();
                console.log('   - userId:', data.userId);
                console.log('     createdAt:', data.createdAt.toDate());
            });
        } else {
            console.log('❌ User não encontrado');
        }
        
        process.exit(0);
    }
    
    checkUser().catch(console.error);
    "
}

# Limpar referral pendente (SharedPreferences)
function clear_pending() {
    print_header "Limpar Referral Pendente"
    
    print_warning "Esta operação remove dados do SharedPreferences"
    print_warning "Use apenas em ambiente de desenvolvimento!"
    echo ""
    
    read -p "Continuar? (y/n) " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Operação cancelada"
        exit 0
    fi
    
    print_warning "Executando flutter clean..."
    flutter clean
    
    print_success "SharedPreferences limpo após próxima execução"
}

# Criar fake users para teste de recompensa
function create_fake_users() {
    print_header "Criar Fake Users"
    
    read -p "Digite o referrerId (usuário que vai receber VIP): " referrer_id
    read -p "Quantos fake users criar? (recomendado: 10): " count
    
    if [ -z "$referrer_id" ] || [ -z "$count" ]; then
        print_error "Parâmetros inválidos"
        exit 1
    fi
    
    print_warning "Criando $count fake users com referrerId=$referrer_id..."
    
    node -e "
    const admin = require('firebase-admin');
    const serviceAccount = require('./service-account-key.json');
    
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
    
    const db = admin.firestore();
    
    async function createFakeUsers() {
        const batch = db.batch();
        
        for (let i = 1; i <= $count; i++) {
            const fakeUserId = 'FAKE_USER_' + Date.now() + '_' + i;
            const userRef = db.collection('Users').doc(fakeUserId);
            
            batch.set(userRef, {
                fullName: 'Test User ' + i,
                referrerId: '$referrer_id',
                referralSource: 'test',
                referralCapturedAt: admin.firestore.FieldValue.serverTimestamp(),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                age: 25,
                status: 'active',
                birthDay: 1,
                birthMonth: 1,
                birthYear: 1999
            });
            
            console.log('✅ Criado fake user', i, '/', $count);
        }
        
        await batch.commit();
        console.log('');
        console.log('✅ Todos os fake users criados!');
        console.log('⏱️  Aguarde 5-10 segundos para Cloud Function processar...');
        
        process.exit(0);
    }
    
    createFakeUsers().catch(console.error);
    "
    
    echo ""
    print_success "Fake users criados! Verifique o Firestore"
}

# Verificar configuração do AppsFlyer
function check_appsflyer_config() {
    print_header "Verificando AppsFlyer Config"
    
    if [ -f "lib/core/constants/constants.dart" ]; then
        print_success "constants.dart encontrado"
        echo ""
        
        echo "📝 Configurações atuais:"
        grep -A 5 "APPSFLYER" lib/core/constants/constants.dart || print_error "Configurações não encontradas"
    else
        print_error "constants.dart não encontrado"
        exit 1
    fi
}

# Testar geração de link
function test_link_generation() {
    print_header "Testar Geração de Link"
    
    read -p "Digite o userId para gerar link: " user_id
    
    if [ -z "$user_id" ]; then
        print_error "userId não pode ser vazio"
        exit 1
    fi
    
    print_warning "Link gerado (formato esperado):"
    echo ""
    echo "https://boora.onelink.me/bFrs/XXXXXXX?pid=af_app_invites&c=user_invite&deep_link_value=invite&deep_link_sub2=$user_id&af_sub1=$user_id&af_dp=boora://main"
    echo ""
    print_warning "Valide se o link real gerado no app tem este formato!"
}

# Watch logs em tempo real
function watch_logs() {
    print_header "Watch Logs (tempo real)"
    
    print_warning "Monitorando logs da Cloud Function..."
    print_warning "Pressione Ctrl+C para parar"
    echo ""
    
    firebase functions:log --only onUserCreatedReferral --follow
}

# Menu principal
function show_menu() {
    echo ""
    print_header "🧪 Referral Debug Tools"
    echo ""
    echo "1) Deploy Cloud Function"
    echo "2) Verificar Logs"
    echo "3) Verificar Firestore (usuário específico)"
    echo "4) Criar Fake Users (teste de recompensa)"
    echo "5) Limpar Referral Pendente"
    echo "6) Verificar AppsFlyer Config"
    echo "7) Testar Geração de Link"
    echo "8) Watch Logs (tempo real)"
    echo "9) Verificar Firebase Setup"
    echo "0) Sair"
    echo ""
    read -p "Escolha uma opção: " choice
    
    case $choice in
        1) deploy_function ;;
        2) check_logs ;;
        3) check_firestore ;;
        4) create_fake_users ;;
        5) clear_pending ;;
        6) check_appsflyer_config ;;
        7) test_link_generation ;;
        8) watch_logs ;;
        9) check_firebase ;;
        0) exit 0 ;;
        *) print_error "Opção inválida" ; show_menu ;;
    esac
    
    echo ""
    read -p "Pressione Enter para voltar ao menu..."
    show_menu
}

# Executar comando direto se passado como argumento
if [ $# -eq 0 ]; then
    show_menu
else
    case $1 in
        deploy) deploy_function ;;
        logs) check_logs ;;
        firestore) check_firestore ;;
        fake) create_fake_users ;;
        clear) clear_pending ;;
        config) check_appsflyer_config ;;
        link) test_link_generation ;;
        watch) watch_logs ;;
        check) check_firebase ;;
        *) 
            print_error "Comando inválido: $1"
            echo ""
            echo "Comandos disponíveis:"
            echo "  deploy    - Deploy Cloud Function"
            echo "  logs      - Verificar logs"
            echo "  firestore - Verificar Firestore"
            echo "  fake      - Criar fake users"
            echo "  clear     - Limpar referral pendente"
            echo "  config    - Verificar AppsFlyer config"
            echo "  link      - Testar geração de link"
            echo "  watch     - Watch logs em tempo real"
            echo "  check     - Verificar Firebase setup"
            exit 1
            ;;
    esac
fi
