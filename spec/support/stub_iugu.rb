def stub_iugu(params = {})
  conf = {
      filename: 'create',
      method: :post,
      url: 'https://api.iugu.com/v1/charge',
      headers: {
        'Accept'=> params[:encoded] ? '*/*' : 'application/json',
        'Accept-Charset'=>'utf-8',
        'Accept-Encoding'=> params[:encoded] ? 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3' : 'gzip, deflate',
        'Accept-Language'=>'pt-br;q=0.9,pt-BR',
        'Content-Type'=> params[:encoded] ? 'application/x-www-form-urlencoded' : 'application/json; charset=utf-8',
        'Host'=>'api.iugu.com',
        'User-Agent'=>'Iugu RubyLibrary'
      },
      body: hash_including({method: 'credit_card'})
  }.merge(params)

  response = JSON.parse File.read("spec/fixtures/iugu_responses/#{conf[:filename]}.json")

  stub_request(conf[:method], conf[:url]).with(
    headers: conf[:headers],
    body: params[:encoded] && conf[:body].is_a?(Hash) ? URI.encode_www_form(conf[:body]) : conf[:body]
  ).to_return(body: response.to_json, status: 200)
end
