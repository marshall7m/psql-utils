apk add --no-cache --virtual .build-deps yarn wget unzip python3 py-pip python3-dev musl-dev linux-headers libxml2 libxml2-dev gcc libxslt-dev

python3 -m venv $VIRTUAL_ENV
source $VIRTUAL_ENV/bin/activate
pip3 install --upgrade pip
pip3 install --no-cache-dir -r requirements.txt

wget -q -O /tmp/git-chglog.tar.gz https://github.com/git-chglog/git-chglog/releases/download/v${GIT_CHGLOG_VERSION}/git-chglog_${GIT_CHGLOG_VERSION}_linux_amd64.tar.gz
tar -zxf /tmp/git-chglog.tar.gz -C /tmp
mv /tmp/git-chglog /usr/local/bin/
wget -q -O /tmp/semtag.tar.gz https://github.com/nico2sh/semtag/archive/refs/tags/v${SEMTAG_VERSION}.tar.gz
tar -zxf /tmp/semtag.tar.gz -C /tmp
mv /tmp/semtag-${SEMTAG_VERSION}/semtag /usr/local/bin/

chmod u+x /usr/local/bin/*

apk del .build-deps
rm -rf /tmp/*
rm -rf /var/cache/apk/*