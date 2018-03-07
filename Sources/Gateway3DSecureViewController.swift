/*
 Copyright (c) 2017 Mastercard
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import UIKit
import WebKit

/// An enum representing the status of the 3DSecure authentication
///
/// - completed: The authentication was completed.  The status parameter will be a gateway's "summaryStatus" field and the ID will be the 3DSecureID that was provided durring the Check3DSecureEnrollment operation.
/// - cancelled: The result if 3DSecure authentication was cancelled by the user.
public enum Gateway3DSecureResult {
    case completed(summaryStatus: String, threeDSecureId: String)
    case error(Gateway3DSecureError)
    case cancelled
}


/// Errors encountered when processing the 3DS redirect
///
/// - missingSummaryStatus: The summaryStatus query parameter was missing
/// - missing3DSecureId: The 3DSecureId query parameter was missing
public enum Gateway3DSecureError: Error {
    case missingSummaryStatus
    case missing3DSecureId
}


/// A view controller to perform 3DSecure 1.0 authentication using an embeded web view.
public class Gateway3DSecureViewController: UIViewController, WKNavigationDelegate {

    /// The internal webview used to perform authentication.
    var webView: WKWebView!
    
    /// The navigation Bar shown at the top of the view
    public var navBar: UINavigationBar!
    
    /// The cancel button allowing the user to abandon 3DS Authentication
    public var cancelButton: UIBarButtonItem!
    
    /// An activity indicatior that is displayed any time there is activity on the web view
    public var activityIndicator: UIActivityIndicatorView!
    
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        setupView()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }
    
    
    /// Used to authenticate the payer using 3DSecure 1.0
    ///
    /// - Parameters:
    ///   - htmlBodyContent: The HTML body provided by the Check3DSecureEnrollment operation
    ///   - handler: A closure to handle the 3DSecure 'WebAuthResult'
    public func authenticatePayer(htmlBodyContent: String, handler: @escaping (Gateway3DSecureViewController, Gateway3DSecureResult) -> Void) {
        self.completion = handler
        self.bodyContent = htmlBodyContent
    }
    
    // MARK: - PRIVATE
    fileprivate var gatewayScheme: String = "gatewaysdk"
    fileprivate var gatewayHost: String = "3dsecure"
    fileprivate var redirectStatusParam: String = "summaryStatus"
    fileprivate var threeDSecureIdParam: String = "3DSecureId"
    
    fileprivate var completion: ((Gateway3DSecureViewController, Gateway3DSecureResult) -> Void)?
    fileprivate var bodyContent: String? = nil {
        didSet {
            loadContent()
        }
    }
    
    fileprivate func setupView() {
        view.backgroundColor = .white
        
        activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
        activityIndicator.hidesWhenStopped = true
        
        cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelAction))
        navigationItem.leftBarButtonItems = [cancelButton]
        navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: activityIndicator)]
        
        navBar = UINavigationBar()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        navBar.backgroundColor = .white
        navBar.items = [self.navigationItem]
        view.addSubview(navBar)
        
        webView = WKWebView()
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        
        var constraints: [NSLayoutConstraint] = []
        if #available(iOSApplicationExtension 11.0, *) {
            constraints.append(NSLayoutConstraint(item: navBar, attribute: .top, relatedBy: .equal, toItem: view.safeAreaLayoutGuide, attribute: .top, multiplier: 1, constant: 0))
        } else {
            constraints.append(NSLayoutConstraint(item: navBar, attribute: .top, relatedBy: .equal, toItem: view, attribute: .top, multiplier: 1, constant: 0))
        }
        
        constraints.append(NSLayoutConstraint(item: navBar, attribute: .leading, relatedBy: .equal, toItem: view, attribute: .leading, multiplier: 1, constant: 0))
        constraints.append(NSLayoutConstraint(item: navBar, attribute: .trailing, relatedBy: .equal, toItem: view, attribute: .trailing, multiplier: 1, constant: 0))
        
        constraints.append(NSLayoutConstraint(item: webView, attribute: .top, relatedBy: .equal, toItem: navBar, attribute: .bottom, multiplier: 1, constant: 0))
        constraints.append(NSLayoutConstraint(item: webView, attribute: .bottom, relatedBy: .equal, toItem: view, attribute: .bottom, multiplier: 1, constant: 0))
        constraints.append(NSLayoutConstraint(item: webView, attribute: .leading, relatedBy: .equal, toItem: view, attribute: .leading, multiplier: 1, constant: 0))
        constraints.append(NSLayoutConstraint(item: webView, attribute: .trailing, relatedBy: .equal, toItem: view, attribute: .trailing, multiplier: 1, constant: 0))
        NSLayoutConstraint.activate(constraints)
    }
    
    fileprivate func loadContent() {
        webView.loadHTMLString(bodyContent ?? "", baseURL: nil)
    }
    
    @objc func cancelAction() {
        completion?(self, .cancelled)
    }
    
    // MARK: - WKNavigationDelegate methods
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activityIndicator.startAnimating()
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, let comp = URLComponents(url: url, resolvingAgainstBaseURL: false), comp.scheme == gatewayScheme, comp.host == gatewayHost {
            decisionHandler(.cancel)
            
            let statusItem = comp.queryItems?.first { (item) -> Bool in
                return item.name == redirectStatusParam
            }
            let idItem = comp.queryItems?.first { (item) -> Bool in
                return item.name == threeDSecureIdParam
            }
            
            guard let status  = statusItem?.value else {
                completion?(self, .error(Gateway3DSecureError.missingSummaryStatus))
                return
            }
            
            guard let threeDSecureId  = idItem?.value else {
                completion?(self, .error(Gateway3DSecureError.missing3DSecureId))
                return
            }
            
            completion?(self, .completed(summaryStatus: status, threeDSecureId: threeDSecureId))
        } else {
            decisionHandler(.allow)
        }
    }
    
}
