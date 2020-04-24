---
title: AWS Security Token Service Kullanarak CLI Üzerinden Operasyon
date: '2020-04-18 21:20:04'
category: blog
author: taylandogan
description: AWS cli araciligi ile STS uzerinden authenticate olma.
tag:
- AWS
- STS
- Authorization
layout: post
---

## AWS IAM
Bildiğimiz gibi, AWS(Amazon Web Services) baya büyük bir bulut bilişim sağlayıcısı. Aynı büyüklükte de bir envantere sahip. Bu envanterde çalışırken en büyük ihtiyaçlarımızdan birisi de güvenlik. Yeni bir AWS hesabı açtığınızda, AWS IAM servisini geçiş yaptığınız zaman karşınıza gelen şu ekranı hatırlıyor musunuz?

![image](/assets/images/aws/sts/iam-status.png)

Tabii ki ilk açtığınızda buradaki yeşil tikler henüz yeşil değil. Aslında bu 5 madde Amazon'un bize sunduğu **best practice**leri. Yazının ana teması IAM yönetimi olmadığı için hepsinden yüzeysel bahsetmem gerekirse;

1. Root, yani kök kullanıcı hesabınız ile giriş yapıp 2 faktör, ya da Amazon tabiri ile Multi-factor, güvenli girşi aktif etmek.
2. Root kullanıcı hesabı ile yeni bir IAM kullanıcısı yaratmak.
3. Bu kullanıcıyı bir gruba eklemek. Haliyle bunun için öncelikle bir grup yaratmamız gerekmekte.
4. IAM kullanıcıları için güvenli bir politika oluşturmak. Bu tam olarak, şifre en az X sayıda karakterden oluşsun içerisinde !'^+ gibi karakterler olsun gibi detayları belirttiğimiz kısım.
5. Access Keylerimizi 90 günde bir rotate ettirmek.

## AWS STS Neden Gerekli?
AWS STS IAM kullanıcılarınızın geçici süreyle authenticate olmasını sağlayan bir web servisidir. Normal şartlarda, elimizde Federated user olmadığını, IAM userlarımızın sadece şirket çalışanları olduğu bir dünyadan bahsedecek olursak, STS ile herhangi bir işiniz olmaması çok doğal. Çünkü normal yaklaşım, kullanıcı üzerine gerekli yetkileri tanımlamak, ekstra güvenlik için bir çaba sarf etmemek. Bunun ne gibi zararları var diye soracak olursak, çalışanlarımızdan biri istemsiz bir şekilde **access key**ini sızdırdığında, bu keye ulaşan herkes, bu key aracılığı ile hesabınız üzerinde tanımladığınız yetkiler çerçevesinde herşeyiyapabilir. Örnek olarak, Eğer kullanıcı üzerinde **EC2FullAccess** yetkisi varsa, bu keye erişimi olan herkes, EC2 üzerinde yeni makine açabilir, instancelarınıza bakabilir, hatta güvenlik duvarı ayarlarınıza dahi erişebilir.

Peki STS bu durumu nasıl çözüyor? Basitçe, tanımlı olan IAM kullanıcınıza o session boyunca geçerli olan yeni bir anahtar çifti oluşturuyor. Bu da session bittikten sonra bu anahtar çiftinin geçerliliğini kaybedeceği için, herhangi bir sızıntı durumunda kafanız biraz daha rahat olabiliyor. Ancak bu kadarı ne yazık ki yeterli değil. Herhangi biri, sizin anahtar çiftinize eriştiğinde, sizin adınıza STS üzerinden hala yeni bir session açabilir.

Peki ne yapacağız? Cevap **MFA**.

## IAM Üzerinden MFA'i Zorunlu Hale Getirmek
İlk adımımız, tüm kullanıcılarımızın MFA'lerinin aktif olduğundan emin olmak olacak. Burada bir parantez açıp, içeriğin Virtual Device yani bildiğimiz 2 Factor Authentication kısmı hakkında bilgi vereceğimi belirtmek istiyorum.

Bunu yaptık, peki sonra? Amazon IAM üzerinden yeni bir policy yaratacağız.


![image](/assets/images/aws/sts/empty-policy-page.png)

Yukarıdaki bölüme geldiğimizde (IAM > Policies > Create policy) aşağıdaki kodu yapıştıracağız.

```
 {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "BlockMostAccessUnlessSignedInWithMFA",
            "Effect": "Deny",
            "NotAction": [
                "iam:CreateVirtualMFADevice",
                "iam:EnableMFADevice",
                "iam:ListMFADevices",
                "iam:ListUsers",
                "iam:ListVirtualMFADevices",
                "iam:ResyncMFADevice",
                "iam:UpdateLoginProfile",
                "iam:ChangePassword",
                "iam:GetAccountPasswordPolicy"
            ],
            "Resource": "*",
            "Condition": {
                "BoolIfExists": {
                    "aws:MultiFactorAuthPresent": "false"
                }
            }
        }
    ]
}
```

Daha sonrasında ileri diyerek, yarattığımız bu kurala bir isim vereceğiz. Ben **DenyMostAccessIfUserHasNoMFA** şekliden yarattım. Daha sonrasıda bu yarattığımız kuralı kullanıcılarımızın olduğu gruba, yada doğrudan kullanıcılara ekliyoruz. Peki şimdi ne olacak? Eğer kullanıcımız STS üzerinden session yaratırken, artık 2FA OTP kodunu da girmek durumunda kalacak.

## Peki Nasıl Login Olacağız?

![image](/assets/images/aws/sts/iam-diagram.png)

Başarmak istediğimiz aşağı yukarı böyle bir şey. Önce STS ile authorize olup, daha sonrasında bize gelen cevaptaki anahtar çiftini kullanarak erişmek istediğimiz servislere erişmek.

Ben bu alışverişi kolaylaştırmak adına küçük bir shell scripti yazdım.

```bash
#!/bin/bash

usage() {
    cat<<EOF
How to?

First, you should provide --user|-u --token|-t --profile|-p --region|-r
As an example; stslogin -u taylan -t 012345 -p default -r eu-central-1

Or

stslogin --user=taylan --token=012345 --profile=default --region=eu-central-1

Also, you can left profilei and region blank, script will automatically think it is the default profile and eu-central-1 as
default region.
EOF
}

# Performs sts login operation.
# $1 is AWS user name, such as taylan
# $2 is the OTP code that your mobile device generate such as 123456
# $3 current aws-cli profile
# $4 AWS Region such as eu-central-1
perform_get_token() {
    sts=$(aws --profile $3 --region $4 sts get-session-token --serial-number arn:aws:iam::$YOUR_AWS_ACCOUNT_ID:mfa/$1 --token-code $2)
    export AWS_ACCESS_KEY_ID=$(echo $sts  | jq .Credentials.AccessKeyId | tr -d '"')
    export AWS_SECRET_ACCESS_KEY=$(echo $sts  | jq .Credentials.SecretAccessKey | tr -d '"')
    export AWS_SESSION_TOKEN=$(echo $sts  | jq .Credentials.SessionToken | tr -d '"')
    export AWS_PROFILE=$3

    /bin/sh -i
}

main() {
    if [ "$#" -lt 2 ]; then
	usage
	exit 1
    fi

    if [ -z $(which jq) ]; then echo "Please install jq first!"; exit 9; fi
    
    while [ "$#" -gt 0 ]; do
	case "$1" in
	    -u) user_name="$2"; shift 2;;
	    -t) token="$2"; shift 2;;
	    -p) profile="$2"; shift 2;;
	    -r) region="$2"; shift2;;
	    
	    
	    --user=*) user_name="${1#*=}"; shift 1;;
	    --token=*) token="${1#*=}"; shift 1;;
            --region=*) region="${1#*=}"; shift1;;
	    --profile=*) profile="${1#*=}"; shift 1;;
	    ----user|--token) echo "$1 requires an argument" >&2; exit 1;;
	    
	    -*) echo "unknown option: $1" >&2; usage; exit 1;;
	    *) handle_argument "$1"; shift 1; usage;; 
	esac
    done

    if [ -z "$profile" ]; then token="profile"; fi
    if [ -z "$region" ]; then region="eu-central-1"; fi

    perform_get_token "$user_name" "$token" "$profile" "$region"

}


main $@
```

Yukaridaki scritpi stslogin.sh olarak kaydedip, **chmod +x stslogin.sh** şeklinde executable yetkisi verdikten sonra, yapacağımız şey gerekli parametreleri doldurmak. Yukarıdaki scripti çalıştırmadan önce, sisteminizde **jq** olduğundan emin olun.

```bash
stslogin.sh --user=taylan \
  --token=OTP_KODU \
  --profile=AWS_PROFİLİNİZ \
  --region=us-west-2
```
	
şeklinde çalıştırdığnız taktirde, eğer girmiş olduğunuz bilgiler doğru ise, sizi yeni bir bash sessionına yönlendirecek. Bu sessionda gerçekleştirmek istediğiniz aws-cli işlemlerinizi gerçekleştirebilirsiniz.

Ya da daha iyisi [benim yazmış olduğum otp](https://github.com/kondanta/notp) aracını kullanarak, otp kodunu cli üzerinden yaratabilirisiniz. Hatta bu şekilde login işlemini bir terminal alias'ına bağlayarak, işlemi kolaylaştırabiliriz. Kurulum için,  makinenizde go olması şart. Golang yok ise, docker ile build alıp, çıkan binaryi kullanabilirsiniz. Ben hali hazırda bilgisayarınızda Go kurulu olduğunu varsayarak devam ediyorum.

* Repo üzerindeki installation açıklamasını takip ederek binaryi kurduk.
* AWS arayüzüne girip My Security Credentials kısmından yeni bir MFA yaratma adımına geldik.
	![image](/assets/images/aws/sts/mfa-screen.png)
	-  Hali hazırda kurulu bir OTP toolunuz var ise, içerisinden hesabınız `secret key`ini kullanarak devam edebilirsiniz.
* Burada ShowQR yazan alanın aşağısında `show secret` var, onu seçiyoruz ve secretı kopyalıyoruz.
	![image](/assets/images/aws/sts/mfa-screen2.png)
* notp --key secret --add <istediğimiz isim> diyoruz
* Daha sonrasında kopyaladığımız keyi buraya yapıştırıyoruz.
![image](/assets/images/aws/sts/notp-token.png)
* notp --key secret --get<istediğimiz isim> aracılığı ile OTP üretip, bunu AWS üzerinde gerekli alanlara girip(totalde 2 defa) MFA kurulumumuzu tamamlıyoruz.

MFA kurulumu bittikten sonra, 

```bash
alias awslogin='awslogin(){
echo "Please enter the secret"
read secret < /dev/tty
token=$(notp --key $secret -q --get <istenen isim>)
stslogin.sh --user=taylan -t $token
}; awslogin '
```
Yukarıdaki aliasımızı bash/zsh rc dosyamıza ekliyoruz. Bu şekilde artık terminal üzerinden işlem yapmak istediğimizde `awslogin` komutunu çalıştırmamız yeterli olacaktır.
