@export()
type portal = {
    name: string?
    location: string?
    skuName: 'Developer' | 'Standard' | 'Premium' | 'Consumption'
    capacity: int?
    publisherEmail: string?
    publisherName: string?
    backends: backend[]
    policies: policy[]?
}

@export() 
type backend = {
    name: string
    description: string
    url: string
    protocol: 'http' | 'soap' | 'wsdl' | 'soap12' | 'http2'
    services: service[]
}

@export() 
type service = {
    name: string
    displayName: string
    subscriptionRequired: bool
    path: string
    protocols: ('http' | 'https' | 'ws' | 'wss')[]
    isCurrent: bool
    policies: policy[]
    operations: operation[]
}

@export() 
type policy = {
    name: string
    format: 'rawxml' | 'rawxml-link' | 'xml' | 'xml-link'
    value: string?
    valueFile: string?
}

@export() 
type operation = {
    name: string
    displayName: string
    method: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH' | 'HEAD' | 'OPTIONS' | 'TRACE'
    urlTemplate: string
    description: string?
    responses: response[]?
    policies: policy[]?
}

@export() 
type response = {
    statusCode: int
    description: string?
    headers: parameter[]?
    representations: representation[]?
}

@export() 
type parameter = {
    name: string
    description: string?
    defaultValue: string?
    required: bool
    schemaId: string?
    type: string
    typeName: string?
    values: string[]?
}

@export() 
type representation = {
    contentType: string
    schemaId: string?
    typeName: string?
}

@export()
type namedValue = {
    name: string
    displayName: string?
    value: string?
    secret: bool
    keyVaultSecretName: string?
}

@description('Source configuration specifying Azure subscription and resource group details')
@export()
type source = {
  name: string
  subscriptionId: string
  resourceGroup: string
}
